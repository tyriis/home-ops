{ inputs, lib, pkgs, config, outputs, ... }:
{
  imports = [
    ./cli/tools.nix
    ./desktop/discord.nix
    ./desktop/file-explorer.nix
    ./desktop/google-chrome.nix
    ./desktop/kitty.nix
    ./desktop/spotify.nix
    ./desktop/vscode.nix
    ./devops/development.nix
    ./devops/kubernetes.nix
  ];

  home.username = "nils";
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.05";


  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [

    # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor

    zsh
    zsh-completions
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-autocomplete
    zsh-forgit
    nix-zsh-completions
    spaceship-prompt

    chezmoi



    # tabby ;(
    barrier

    obsidian

    # wayland only
    # watershot currently broken
    grim
    slurp
    wl-clipboard
    libnotify

    # wayland terminal emulator, we can use alacritty aswell



    # wayland notification daemon
    mako




  ];

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
