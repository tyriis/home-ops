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

    # inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
    # inputs.ags.packages.${pkgs.system}.default



    # wayland notification daemon
    mako
    wofi
    # screenshot
    swappy

    # inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
    # https://github.com/hyprwm/Hyprland/issues/6320#issuecomment-2243109637
    nwg-look
    rose-pine-cursor
  ];
  services.mako = {
    enable = true;
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
  home.pointerCursor = {
      name = "rose-pine-hyprcursor";
      package = inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default;
      size = 32; # Adjust as needed
    };
}
