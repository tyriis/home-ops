# Baseline module for docker-lane hosts (design: docs/superpowers/specs/2026-11-07-nixos-hardened-docker-lane-design.md).
# Encodes the pilot-proven state of bifrostix (2026-11-14). Impermanence and
# LUKS/TPM2 sealing are the remaining deliberate follow-ups per the spec
# acceptance list — tracked in #11792. The hardening baseline
# (sshd/nftables/sysctl) lives in ./hardening.nix (phase A, 2026-11-15).
{ pkgs, ... }:
{
  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_6_18; # LTS pin — no silent channel bumps

  # Memory: compressed zram instead of disk swap (headless, no hibernation)
  zramSwap.enable = true;

  # Networking: systemd-networkd; NetworkManager is a desktop daemon
  networking.useNetworkd = true;

  # Host service surface: sshd + dockerd + time sync (per spec section 3)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Escape lane: SSH from the initrd (port 2222, root key from
  # users.users.root below). Recovery shell that works when root is not
  # mounted yet — the drill that makes it proven lives with the
  # impermanence plan (2026-11-16 spec), and Phase C LUKS unlock reuses it.
  # 26.11 removed scripted stage 1: the initrd is systemd unconditionally,
  # networking is systemd-networkd, and the system .network units are
  # reused, so DHCP applies in stage 1 too. Each host must declare its
  # NIC driver in boot.initrd.kernelModules — initrd networking does not
  # include it, and no driver means no listener (bifrostix: e1000e).
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      # Reuse the live host key so the fingerprint is the one operators
      # already trust; build-time read, baked into the initrd as a secret.
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  # Drill hold: DORMANT by default. On an unencrypted root the stage-1
  # window is a few seconds — too narrow to prove the 2222 escape lane
  # reliably. Create the condition path (drill generations only) and the
  # initrd holds 120s with sshd reachable, so a drill can log in at
  # leisure. Continue a held boot with: systemctl isolate
  # initrd-switch-root.target
  boot.initrd.systemd.services.initrd-drill-hold = {
    description = "Hold stage 1 for the initrd-SSH drill";
    after = [ "sshd.service" ];
    wantedBy = [ "initrd-switch-root.target" ];
    before = [ "initrd-switch-root.target" ];
    unitConfig.ConditionPathExists = "/etc/initrd-drill-hold";
    serviceConfig.Type = "oneshot";
    script = "sleep 120";
  };

  # Docker platform (spec, "Docker daemon, declarative"):
  # json-file as daemon default so unmanaged strays rotate too (#11541 pattern).
  virtualisation.docker = {
    enable = true;
    storageDriver = "overlay2";
    logDriver = "json-file";
    daemon.settings = {
      "log-opts" = {
        max-size = "10m";
        max-file = "3";
      };
    };
  };

  # Operators
  users.users.root.openssh.authorizedKeys.keys = [
    # jarvis TPM key (SHA256:ma2kHnRhbSUzCmso3XxWJ4qeb3qWb/onH4HQDc50rXc)
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPUV+o1BXyB0OiRdvqk+NPHT0JHtMZz5eTpSbJDVgKtxw4nNC+bwIaJBUC6N7CzPzAf9RZ/l4Diw5IacUmbHgDQ= jarvis@jarvis"
  ];
  users.users."nils" = {
    isNormalUser = true;
    description = "nils";
    extraGroups = [ "wheel" ];
  };

  console.keyMap = "de-latin1-nodeadkeys";

  # Flake builds of these hosts are run from this tree on-target
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
