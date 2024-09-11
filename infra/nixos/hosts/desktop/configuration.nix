# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ inputs, config, lib, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../users.nix
      ../../fonts.nix
      ../../modules/gnome-keyring.nix
      ../../modules/openssh.nix
      ../../modules/neovim.nix
      ../../modules/hyprland.nix
      ../../modules/ags.nix
      ../../modules/docker.nix
      ../../modules/system-packages.nix
      ../../modules/lutris.nix
      ../../modules/syncthing.nix
      ../../modules/plasma.nix
      ../../modules/nvidia.nix
    ];

  # enable nix-flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # LUKS device to open before mounting / [root]
  boot.initrd.luks.devices = {
    luks = {
      device = "/dev/disk/by-uuid/3c63b5b9-4d3f-4253-a6d9-de108bdb7421";
      allowDiscards = true;
      preLVM = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.plymouth.enable = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;


  # btrfs ;)
  boot.supportedFilesystems = [ "btrfs" ];

  hardware.enableAllFirmware = true;

  # Define hostname.
  networking.hostName = "desktop";
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Vienna";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_DK.UTF-8";

  # Nice font for the framebuffer console.
  console = {
    earlySetup = true;
    # https://www.if-not-true-then-false.com/2024/fedora-terminus-console-font/
    font = "${pkgs.terminus_font}/share/consolefonts/ter-116n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "de";
    # useXkbConfig = true; # use xkbOptions in tty.
  };

  # links /libexec from derivations to /run/current-system/sw
  environment.pathsToLink = [ "/libexec" ];

  # List services that you want to enable:

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;


  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8000 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?


  # hardware.pulseaudio.enable = true;
  # hardware.pulseaudio.support32Bit = true; ## If compatibility with 32-bit applications is desired.
  nixpkgs.config.pulseaudio = true;

  # adjust size of /run/user/1000 this is required to compile f.e. node with mise
  services.logind.extraConfig = ''
    RuntimeDirectorySize=3G
  '';
  # Allow Chrome screen sharing https://github.com/NixOS/nixpkgs/issues/91218
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
    jack.enable = true;
  };


  xdg = {
    portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal
      ];
      configPackages = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal

      ];
      xdgOpenUsePortal = true;
    };
  };

  environment.systemPackages = [
    # TODO find a way to load this with home-manager
    inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
    inputs.ags.packages.${pkgs.system}.default
    pkgs.smartmontools
  ];
  system.activationScripts.linkCursorTheme = ''
    mkdir -p /usr/share/icons
    ln -sfn ${inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default}/share/icons/rose-pine-hyprcursor /usr/share/icons/rose-pine-hyprcursor
  '';

  services.smartd = {
    enable = true;
    autodetect = true;
  };
}
