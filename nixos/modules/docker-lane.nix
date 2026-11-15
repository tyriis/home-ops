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
