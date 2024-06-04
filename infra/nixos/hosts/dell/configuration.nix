# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, lib, pkgs, ... }:
# let
#   unstable = import <nixos-unstable> {
#     config.allowUnfree = true;
#   };
# in
{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../users.nix
      ../../fonts.nix
      ../../modules/openssh.nix
      ../../modules/neovim.nix
    ];

  # enable nix-flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfree = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # btrfs ;)
  boot.supportedFilesystems = [ "btrfs" ];

  hardware.enableAllFirmware = true;

  # Define hostname.
  networking.hostName = "dell";
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
    font = "${pkgs.terminus_font}/share/consolefonts/ter-120n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "de";
    # useXkbConfig = true; # use xkbOptions in tty.
  };

  # links /libexec from derivations to /run/current-system/sw
  environment.pathsToLink = [ "/libexec" ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  #  # Enable i3
  #  services.xserver = {
  #    enable = true;
  #    layout = "de";
  #
  #    desktopManager = {
  #      xterm.enable = false;
  #      xfce = {
  #        enable = true;
  #        noDesktop = true;
  #        enableXfwm = false;
  #      };
  #    };
  #
  #    displayManager = {
  #      defaultSession = "xfce+i3";
  #    };
  #
  #    windowManager.i3 = {
  #      enable = true;
  #      extraPackages = with pkgs; [
  #        dmenu #application launcher most people use
  #        rofi # dmenu but better ;)
  #        i3status # gives you the default i3 status bar
  #        i3lock #default i3 screen locker
  #        betterlockscreen # some better lockscreen
  #        i3blocks #if you are planning on using i3blocks over i3status
  #        # i3blocks-contrib
  #      ];
  #    };
  #  };


  # Enable the Plasma 6 Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "de";
  services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable 'sudo' for the user.
  #   packages = with pkgs; [
  #     firefox
  #     tree
  #   ];
  # };

  # users.users.nils = {
  # isNormalUser = true;
  # createHome = true;
  # home = "/home/nils";
  # extraGroups = [ "wheel" "networkmanager" "audio"];
  # openssh.authorizedKeys.keys = let
  #   authorizedKeys = pkgs.fetchurl {
  #     url = "https://github.com/tyriis.keys";
  #     sha256 = "HQJOzIzdTcapfYRMueESfmlWGaylteMBLU8AqqwMTS4=";
  #   };
  # in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  # packages = with pkgs; [
  #   go-task
  #   chezmoi
  #   vault
  #   age
  #   sops
  #   zsh
  #   zsh-autosuggestions
  #   zsh-syntax-highlighting
  #   spaceship-prompt
  #   nodePackages.zx
  #   unstable.vscode
  #   # tabby ;(
  #   barrier
  #   fluxcd
  #   kubectl
  #   kubernetes-helm
  #   k9s
  # ];
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    zsh
    spaceship-prompt
    htop
    alacritty
    nodePackages.zx
    unstable.google-chrome

    # build tools
    gcc
    gnumake

    # python
    python3
    # google-chrome
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable zsh.
  programs.zsh.enable = true;

  # Enable VSCode server.
  programs.nix-ld.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true; ## If compatibility with 32-bit applications is desired.
  nixpkgs.config.pulseaudio = true;

}
