# Hardening baseline for docker-lane hosts (phase A per research 2026-11-15).
# Scope: sshd policy, nftables default-deny input, kernel sysctl/params.
# Deliberately NOT here: forward-chain policy (Docker owns FORWARD today),
# egress filtering (monitor-only until designed), modules_disabled/lockdown
# (brick risk without preloaded-module audit), LUKS/TPM + impermanence (phases B/C).
{
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
}
