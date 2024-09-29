{pkgs, ...}:
{
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    htop
    btop

    # unstable.google-chrome

    # build tools
    gcc
    gnumake

    # python
    python3
    # google-chrome

    plymouth
    nixos-bgrt-plymouth

    nodejs
  ];

  # Enable zsh.
  programs.zsh.enable = true;

  # Enable VSCode server.
  programs.nix-ld.enable = true;
}
