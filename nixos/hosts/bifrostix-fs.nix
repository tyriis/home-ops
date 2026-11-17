# bifrostix host filesystem layout — Phase B impermanence flip.
# Design: docs/superpowers/specs/2026-11-16-bifrostix-impermanence-btrfs-design.md
#
# Hand-owned; lives beside ./hardware-bifrostix.nix, never inside it (that
# file keeps its generate-config "do not modify" contract). This is the
# layout the migration seeds before the flip: `/` moves from the unnamed
# FS_TREE to the named `@` subvolume, wiped from a read-only `@base` each
# boot, and only the allow-list below outlives a reboot.
#
# `/nix` and `/home` are unchanged subvolume mounts — the store is not a
# root concern and must never roll back (generations are state).
{ config, lib, pkgs, ... }:
let
  fsUUID = "4e2aa3de-4b26-4a84-bde5-13465a488466";
  dev = "/dev/disk/by-uuid/${fsUUID}";
in
{
  imports = [ ../modules/impermanence-btrfs.nix ];

  impermanence = {
    enable = true;
    device = dev;

    # Bind sources the wipe pre-creates; each has a matching fileSystems
    # entry below.
    persistBinds = [
      "/etc/ssh"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log/audit"
      "/root/nixos"
    ];

    # bifrostix's persist surface. Empty/missing → the wipe halts rather
    # than boot an empty /var/lib/nixos (uid renumbering, ownership ruin).
    sentinelDirs = [
      # NB: this pin's /var/lib/nixos has no ids/ subdir — live proof
      # 2026-11-17: uid-map, gid-map, declarative-{users,groups},
      # auto-subuid-map. A wrong sentinel here fail-closed a boot at
      # stage-1 (the design working), but only after costing a console.
      { path = "var/lib/nixos"; check = "nonempty"; }
      { path = "etc/ssh"; check = "hostkeys"; }
      { path = "var/lib/systemd"; check = "present"; }
    ];
  };

  # Root: FS_TREE -> named `@`. mkForce overrides the generate-config
  # entry without editing hardware-bifrostix.nix.
  fileSystems."/" = lib.mkForce {
    device = dev;
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  # The allow-list roots, all mounted before stage-2 /etc activation
  # (neededForBoot) — the uid-renumbering race this design exists to kill.
  fileSystems."/persistent" = {
    device = dev;
    fsType = "btrfs";
    options = [ "subvol=@persistent" ];
    neededForBoot = true;
  };

  fileSystems."/persistent/docker" = {
    device = dev;
    fsType = "btrfs";
    options = [ "subvol=@docker" ];
    neededForBoot = true;
  };

  # Its own subvolume, not a bind: journald has DefaultDependencies=no and
  # runs Before=sysinit.target — a bind at local-fs loses that race and
  # journald writes only to the volatile runtime journal (a green
  # `journalctl --verify` of an empty box).
  fileSystems."/var/log/journal" = {
    device = dev;
    fsType = "btrfs";
    options = [ "subvol=@journal" ];
    neededForBoot = true;
  };

  # Content binds (everything else under /persistent).
  # neededForBoot IS MANDATORY at 26.11: stage-2 activation does not exist
  # — the whole activation script runs in the INITRD (unit
  # initrd-nixos-activation) BEFORE switch-root, so anything it reads or
  # writes (/var/lib/nixos = uid/gid state!) must be mounted stage-1.
  # Verified 2026-11-17: `systemctl show nixos-activation` on the live
  # 26.11 host reports no such unit.
  # SSH host keys. The sentinel asserts they exist under @persistent
  # every boot; without this bind the assertion guards a surface that
  # is never mounted — keys would seed, assert, and still regenerate.
  fileSystems."/etc/ssh" = {
    device = "/persistent/etc/ssh";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
  fileSystems."/var/lib/nixos" = {
    device = "/persistent/var/lib/nixos";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
  fileSystems."/var/lib/systemd" = {
    device = "/persistent/var/lib/systemd";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
  fileSystems."/var/log/audit" = {
    device = "/persistent/var/log/audit";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
  # The rebuild source. Seeded during migration: a flake build needs a tree
  # (docker-lane builds from it); "nixos dir" once read as /var/lib/nixos
  # and left a host with nothing to rebuild from.
  fileSystems."/root/nixos" = {
    device = "/persistent/root/nixos";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };

  # tmp surfaces. boot.tmp.useTmpfs covers /tmp only; /var/tmp is separate.
  # The old top-level tmp / var/tmp subvolumes go unused after the flip and
  # are dropped in the cleanup pass.
  boot.tmp.useTmpfs = true;
  fileSystems."/var/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "noatime" "mode=1777" ];
  };

  # Docker data-root on its own subvolume. RequiresMountsFor, or dockerd can
  # initialise an empty store under the ephemeral root before the mount
  # lands — silent split-brain.
  virtualisation.docker.daemon.settings."data-root" = "/persistent/docker";
  systemd.services.docker = {
    requires = [ "persistent-docker.mount" ];
    after = [ "persistent-docker.mount" ];
  };

  # Static identity: the store re-renders it every activation, so a
  # deterministic machine id needs no persistence. The v262 EN DUID derives
  # from it, keeping the controller's .31 reservation addressing stable.
  environment.etc."machine-id".text = "ba8478fc635a4f08ab4fd710e687aa3f\n";

  # Debug posture for the PoC console era (revisit at Phase C hardening):
  # forward the stage-2 journal to the console so a failed boot names its
  # own killer on screen instead of vanishing into a runtime-only journal
  # lost at the next reset.
  # 2026-11-17: systemd.default_timeout_start_sec=20 REMOVED — it is a
  # global crutch and it starved exactly the phase that killed us: device
  # arrival for the NVMe ("Timed out waiting for devices to appear",
  # x-initrd mounts failing ENOENT at 4.8s with 20 s caps instead of the
  # 90 s device budget). Debug convenience must not eat boot physics.
  boot.kernelParams = [ "systemd.journald.forward_to_console=1" ];

  # Boot forensics: stream the console to the jarvis box over UDP. The
  # netconsole module is loaded in stage-1 (after the initrd network is
  # online — the same path the 2222 drill proves) and survives
  # switch-root, so a stage-2 death (12:3x boot: nixos-activation
  # "no such file", zero journal trace) prints itself out to a witness
  # instead of a dark monitor.
  # 2026-11-17 RETIRED: NixOS's 6.18.63 tree ships NO netconsole.ko —
  # CONFIG_NETCONSOLE is unset; both capture attempts were silent because
  # the module simply does not exist. The black-box recorder below is the
  # witness instead — now self-mounting so it survives the failure.
  # boot.initrd.systemd.services.netconsole-capture = { ... } (removed)

  # Black-box recorder — INITRD edition (2026-11-17). Critical lesson:
  # 26.11 has NO stage-2 — the old stage-2 emergency.target recorder never
  # fired once (zero dumps ever written; verified on @persistent after
  # three silent deaths). In 26.11 every failure either lands in the
  # initrd's emergency.target ("Failed to switch root, entering emergency
  # mode" — 11:52 console proof) or dies before anything. This unit must
  # therefore live in the initrd.
  #
  # Self-mounting: mounts @persistent + ESP from raw device paths — never
  # trusts the mount graph under investigation. Copies raw .journal files
  # when journalctl is absent (initrd tooling is minimal; the raw files
  # decode offline via journalctl --file). Writes ESP copy FIRST (btrfs
  # independence), caps at 5MB, syncs, reboots itself.
  boot.initrd.systemd.services.impermanence-boot-dump = {
    description = "Impermanence: persist initrd journal on emergency, then reboot";
    wantedBy = [ "emergency.target" ];
    unitConfig.DefaultDependencies = false;
    # 2026-11-17 lesson: a raw ExecStart -> pkgs.writeShellScript does NOT
    # land in the initrd closure — the unit fired at emergency.target and
    # died "No such file or directory" (execve: interpreter/script absent).
    # The `script` attribute is the 26.11 initrd-safe path: NixOS renders
    # it and includes it, exactly like the proven impermanence-wipe unit.
    script = ''
        TS=$(date +%Y%m%dT%H%M%S)
        mkdir -p /mnt/dump-p /mnt/dump-esp
        BUMP=""
        if mount -o subvol=@persistent /dev/disk/by-uuid/4e2aa3de-4b26-4a84-bde5-13465a488466 /mnt/dump-p 2>/dev/null; then
          mkdir -p /mnt/dump-p/debug
          BUMP=/mnt/dump-p/debug
        fi
        dump_journal() {
          # $1 = destination dir
          if command -v journalctl >/dev/null 2>&1; then
            journalctl -b --no-pager > "$1/boot-failure-$TS.txt" 2>&1 || true
          else
            # raw journal files + kernel ring — decode with:
            #   journalctl --file=<file>   (offline)
            find /run/log/journal -name '*.journal' 2>/dev/null | while read -r f; do
              cp "$f" "$1/raw-journal-$TS-$(basename "$f")" 2>/dev/null
            done
            dmesg > "$1/dmesg-$TS.txt" 2>&1 || true
            echo "boot-dump: journalctl absent; raw journal + dmesg written" > "$1/boot-failure-$TS.txt"
          fi
        }
        # ESP first: independent medium. Device path — never the udev UUID
        # link (case rules broke a forensic script once; it stays device).
        if mount /dev/nvme0n1p1 /mnt/dump-esp 2>/dev/null; then
          dump_journal /mnt/dump-esp
          head -c 5242880 /mnt/dump-esp/*"$TS"* >/dev/null 2>&1 || true
          umount /mnt/dump-esp 2>/dev/null || sync
        fi
        if [ -n "$BUMP" ]; then
          dump_journal "$BUMP"
          umount /mnt/dump-p 2>/dev/null || sync
        fi
        sync
    '';
    serviceConfig = {
      ExecStartPost = "${pkgs.systemd}/bin/systemctl reboot --no-block";
      TimeoutStartSec = 60;
    };
  };

  # Root-cause of gen27-36 (11 deaths, 1 lucky one-shot survivor),
  # proven 2026-11-17: the fstab generator orders mounts by MOUNTPOINT
  # prefix only — it never orders a bind after the mount that provides
  # its SOURCE. Every content bind above has its device path under
  # /persistent, a sibling x-initrd mount. At ~4.8s the five bind
  # sources (plus the crutch-killed nix.mount — sixth failure on the
  # 11:52 console) lose the coin flip, fail "Can't look up mountpoint:
  # ENOENT", get killed by "start request repeated too quickly", and
  # switch-root fails on the dead units. The generator cannot fix this;
  # declare the edges it does not know about. x-initrd units carry the
  # sysroot- prefix in the initrd (exact names console-verified), plain
  # names in stage-2.
  boot.initrd.systemd.units = lib.listToAttrs (map (n: {
    name = "sysroot-${n}.mount";
    value = {
      unitConfig = {
        Requires = [ "sysroot-persistent.mount" ];
        After = [ "sysroot-persistent.mount" ];
      };
    };
  }) [ "etc-ssh" "var-lib-nixos" "var-lib-systemd" "var-log-audit" "root-nixos" ]);
  systemd.units = lib.listToAttrs (map (n: {
    name = "${n}.mount";
    value = {
      unitConfig = {
        Requires = [ "persistent.mount" ];
        After = [ "persistent.mount" ];
      };
    };
  }) [ "etc-ssh" "var-lib-nixos" "var-lib-systemd" "var-log-audit" "root-nixos" ]);

  # Host keys: persist the data under /persistent/etc/ssh (contents, not an
  # /etc bind) and point the option at it. Assigning hostKeys replaces the
  # default set, so declare the full set; missing keys are generated at
  # these paths by sshd-keygen.service, landing in /persistent and
  # surviving. Migration seeds the current set.
  services.openssh.hostKeys = [
    { path = "/persistent/etc/ssh/ssh_host_rsa_key"; type = "rsa"; }
    { path = "/persistent/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
    { path = "/persistent/etc/ssh/ssh_host_mldsa44_ed25519_key"; type = "mldsa44-ed25519"; }
  ];
}
