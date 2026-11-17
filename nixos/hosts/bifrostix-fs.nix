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
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log/audit"
      "/root/nixos"
    ];

    # bifrostix's persist surface. Empty/missing → the wipe halts rather
    # than boot an empty /var/lib/nixos (uid renumbering, ownership ruin).
    sentinelDirs = [
      { path = "var/lib/nixos/ids"; check = "nonempty"; }
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
