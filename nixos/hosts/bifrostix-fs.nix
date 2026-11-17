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

  # Black-box recorder for the no-eyeballs-on-console era. If stage-2
  # reaches emergency.target (every local-fs failure does, and a
  # stage-1 failure means initrd-2222 instead — covered by the drill),
  # persist this boot's journal to @persistent, sync, then reboot.
  # Loader default is held at a known-good gen, so the reboot lands
  # the host back in a state I can drive, and the cause of death is
  # on disk by the time it boots — no human in the failure loop.
  systemd.services.impermanence-boot-dump = {
    description = "Impermanence: persist boot journal on emergency, then reboot";
    wantedBy = [ "emergency.target" ];
    after = [ "systemd-journald.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal";
      ExecStart = pkgs.writeShellScript "impermanence-boot-dump" ''
        # Self-mounting black box: a failure that breaks the x-initrd bind
        # chain leaves /persistent missing, so a dump written there is a
        # dump written to the ephemeral root — lost. Mount our own storage
        # from raw devices, write two copies (btrfs + ESP), never trust
        # the mount graph we are investigating.
        TS=$(date +%Y%m%dT%H%M%S)
        LOG=/dev/null
        mkdir -p /mnt/dump-p /mnt/dump-esp
        if mount -o subvol=@persistent /dev/disk/by-uuid/4e2aa3de-4b26-4a84-bde5-13465a488466 /mnt/dump-p 2>/dev/null; then
          mkdir -p /mnt/dump-p/debug
          LOG=/mnt/dump-p/debug/boot-failure-$TS.txt
        fi
        # ESP copy first: independent medium, survives every btrfs story.
        # Device path, not UUID link: a forensic script must not depend on
        # udev name case rules for the vfat serial.
        if mount /dev/nvme0n1p1 /mnt/dump-esp 2>/dev/null; then
          journalctl -b --no-pager 2>&1 | head -c 5242880 > /mnt/dump-esp/boot-failure-$TS.txt 2>&1 || true
          umount /mnt/dump-esp 2>/dev/null || sync
        fi
        if [ "$LOG" != /dev/null ]; then
          journalctl -b --no-pager > "$LOG" 2>&1 || true
          journalctl -b -p warning --no-pager > "$LOG.warn" 2>&1 || true
        fi
        sync
      '';
      ExecStartPost = "${pkgs.systemd}/bin/systemctl reboot --no-block";
      TimeoutStartSec = 60;
    };
  };

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
