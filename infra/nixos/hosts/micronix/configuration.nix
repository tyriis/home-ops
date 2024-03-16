# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../users.nix
    ];

  # enable nix-flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.consoleMode = "auto";

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "micronix"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Vienna";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_DK.UTF-8";
    LC_IDENTIFICATION = "en_DK.UTF-8";
    LC_MEASUREMENT = "en_DK.UTF-8";
    LC_MONETARY = "en_DK.UTF-8";
    LC_NAME = "en_DK.UTF-8";
    LC_NUMERIC = "en_DK.UTF-8";
    LC_PAPER = "en_DK.UTF-8";
    LC_TELEPHONE = "en_DK.UTF-8";
    LC_TIME = "en_DK.UTF-8";
  };

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

  # Configure keymap in X11
  # services.xserver = {
  #   layout = "de";
  #   xkbVariant = "nodeadkeys";
  # };

  # Define a user account. Don't forget to set a password with 'passwd'.
  # users.users.nils = {
  #   isNormalUser = true;
  #   createHome = true;
  #   home = "/home/nils";
  #   extraGroups = [ "wheel" "networkmanager" "docker" ];
  #   openssh.authorizedKeys.keys = let
  #     authorizedKeys = pkgs.fetchurl {
  #       url = "https://github.com/tyriis.keys";
  #       sha256 = "HQJOzIzdTcapfYRMueESfmlWGaylteMBLU8AqqwMTS4=";
  #     };
  #   in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  #   packages = with pkgs; [ ];
  # };

  # users.users.jasmin = {
  #   isNormalUser = true;
  #   createHome = true;
  #   home = "/home/jasmin";
  #   extraGroups = [ "wheel" "networkmanager" "docker" ];
  #   openssh.authorizedKeys.keys = let
  #     authorizedKeys = pkgs.fetchurl {
  #       url = "https://github.com/jazzlyn.keys";
  #       sha256 = "Xeu/F1/mWxWwE4uN+Jar+R25ChQx0EEYZxE0E3Yxj5s=";
  #     };
  #   in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  #   packages = with pkgs; [ ];
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    htop
    go-task
    nodePackages.zx
    kubectl
    clusterctl
    talosctl
    k9s
    pinentry-curses # gpg: https://discourse.nixos.org/t/cant-get-gnupg-to-work-no-pinentry/15373/2
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
    # openFirewall = true;
  };

  # Enable zsh.
  programs.zsh.enable = true;

  # Enable GnuPG agent with socket-activation for every user session.
  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "curses";
  programs.gnupg.agent.enableSSHSupport = true;

  # Enable docker
  virtualisation.docker.enable = true;

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

  # disable powermanagment
  # https://discourse.nixos.org/t/stop-pc-from-sleep/5757
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Enable VSCode server
  # https://nixos.wiki/wiki/Visual_Studio_Code#nix-ld
  programs.nix-ld.enable = true;

  # Enable neovim as default editor.
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  programs.neovim.vimAlias = true;
  programs.neovim.viAlias = true;
}
