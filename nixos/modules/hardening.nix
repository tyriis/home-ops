# Hardening baseline for docker-lane hosts (phase A per research 2026-11-15).
# Scope: sshd policy, nftables default-deny input, kernel sysctl/params.
# Deliberately NOT here: forward-chain policy (Docker owns FORWARD today),
# egress filtering (monitor-only until designed), modules_disabled/lockdown
# (brick risk without preloaded-module audit), LUKS/TPM + impermanence (phases B/C).
{ lib, ... }:
let
  # journald's render path flipped between the locked rev (26.05.x) and
  # nixos-unstable (now 26.11.x): `storage` renamed into `settings.Journal`
  # and `extraConfig` removed outright — a hard assert, silently dropping
  # Seal=yes (build gate caught it, run 43771273732). Version is monotonic
  # and pure to evaluate; probing `options` from a module of the same
  # evalModules pass instead would recurse.
  # If a hand-picked pin ever lands between the remap merge and the
  # 26.11 version bump, the old branch misroutes LOUD — assert at gate
  # time, never silently.
  journaldSettingsRender = lib.versionAtLeast lib.version "26.11";
in
{
  imports = [
    # journald: survive reboots, and prove the log was not edited afterwards.
    (lib.optionalAttrs journaldSettingsRender {
      services.journald.settings.Journal = {
        Storage = "persistent";
        Seal = "yes";
      };
    })
    (lib.optionalAttrs (!journaldSettingsRender) {
      services.journald.storage = "persistent";
      services.journald.extraConfig = ''
        Seal=yes
      '';
    })
  ];

  # ---- sshd: complete the key-only lane --------------------------------
  # Do not pin ciphers/KEX: OpenSSH 10.x defaults are post-quantum hybrid;
  # hand-curated lists are downgrades in disguise.
  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    AuthenticationMethods = "publickey";
    MaxAuthTries = 3;
    LoginGraceTime = 30;
    MaxStartups = "10:30:100";
    ClientAliveInterval = 300;
    ClientAliveCountMax = 3;
    X11Forwarding = false;
  };

  # ---- nftables: default-deny input, self-owned ruleset -----------------
  # NixOS firewall module off; this ruleset is the only input policy.
  # Docker's published-port DNAT path traverses PREROUTING/FORWARD in its own
  # tables (iptables-nft shim) and is unaffected by this input hook; the
  # forward chain stays accept until the DOCKER-USER policy phase.
  # NOTE: an nftables SERVICE RESTART mid-run flushes the whole ruleset,
  # including Docker's shim tables — `systemctl restart docker` right after
  # to re-sync published ports. Cold boot has no such race (dockerd starts
  # after nftables) — proven on bifrostix 2026-11-15.
  networking.firewall.enable = false;
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {
        chain input {
          type filter hook input priority 0; policy drop;

          ct state established,related accept
          ct state invalid drop
          iif "lo" accept

          # ICMP: keep error + NDP types or IPv6 silently breaks
          icmp type { destination-unreachable, time-exceeded, parameter-problem, echo-request } accept
          icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept
          meta l4proto icmpv6 icmpv6 type nd-redirect drop

          # SSH: any source (LAN is edge-protected by the gateway), throttled
          tcp dport 22 ct state new limit rate 30/minute burst 20 packets accept

          # Rate-limited log of new drops, then fall through to policy drop
          ct state new counter limit rate 10/minute log prefix "nft-input-drop: "
        }

        chain forward {
          type filter hook forward priority 0; policy accept;
          # Docker traffic (overlay2 bridge + published ports) lives here.
          # Tighten in the egress/forward policy phase, not before.
        }

        chain output {
          type filter hook output priority 0; policy accept;
        }
      }
    '';
  };

  # ---- kernel: sysctl baseline (CIS-L1/kspp consensus, Docker-safe) ----
  # rp_filter=2 (loose): strict mode can drop correctly-NAT'd container
  # return paths. ip_forward stays enabled — required by Docker.
  # unprivileged BPF off (BPF loader needs CAP_BPF); perf_event_paranoid 3.
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.randomize_va_space" = 2;
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "vm.mmap_min_addr" = 65536;
    "dev.tty.ldisc_autoload" = 0;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    "net.ipv4.conf.all.log_martians" = 1;
    # Headless doctrine: panic is recovery on an unattended box.
    "kernel.softlockup_panic" = 1;
    "kernel.panic" = 30;
    # NOT set: kernel.modules_disabled (write-once, breaks overlay2/nft
    # autoloading), hung_task_panic (a wedged volume would panic the host),
    # user.max_user_namespaces=0 (kills runc).
  };

  boot.kernelParams = [
    "slab_nomerge"
    "page_poison=1"
    "page_alloc.shuffle=1"
    "debugfs=off"
  ];

  # ---- integrity + audit (phase A2, 2026-11-15) --------------------------
  # journald persistent + Seal render per-pin below (option-shape flipped
  # between the locked rev and current nixos-unstable).

  # auditd: the second channel journald lacks — execve/euid attribution.
  # -w watches + only two cheap syscall families (time change, module load).
  # Deliberately absent: syscall-level execve tracing (CIS L2 noise),
  # -e 2 immutable mode and failure=panic (brick-adjacent on a remote box),
  # watches under /var/lib/docker (fires on every pull/build — audit the
  # control plane, not the data plane).
  # NixOS quirk: /etc files are materialized store symlinks; a store-path
  # change means a rebuild happened, which is visible in generations anyway.
  security.auditd.enable = true;
  security.audit.rules = [
    "-b 8192"
    "-w /etc/passwd -p wa -k identity"
    "-w /etc/shadow -p wa -k identity"
    "-w /etc/group -p wa -k identity"
    "-w /etc/sudoers -p wa -k identity"
    "-w /etc/sudoers.d -p wa -k identity"
    "-w /etc/ssh/sshd_config.d -p wa -k sshd"
    "-w /etc/audit/ -p wa -k auditconfig"
    "-w /var/log/audit/ -p wa -k logchange"
    "-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change"
    "-w /etc/localtime -p wa -k time-change"
    "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules"
    "-w /etc/modprobe.d -p wa -k modules"
    "-w /run/current-system/sw/bin/sudo -p x -k privesc"
    "-w /run/current-system/sw/bin/su -p x -k privesc"
    "-w /etc/docker -p wa -k docker"
    "-w /run/docker.sock -p wa -k docker"
  ];

  # OOM doctrine: zram (already on) buys time; earlyoom spends it — kills the
  # runaway before global thrash. Not paired with systemd-oomd (never both).
  services.earlyoom = {
    enable = true;
    # Kill container-y offenders slightly earlier than default thresholds.
    freeMemThreshold = 5;
  };

  # (polkit auth-reuse window + pkexec-wrapper opt-in: this pin's polkit
  # module exposes only JS extraConfig — no polkitd.conf options yet.
  # Re-add `settings.Polkitd.ExpirationSeconds = 30` and
  # `enablePkexecWrapper = false` on the first flake update carrying 26.11.)
}
