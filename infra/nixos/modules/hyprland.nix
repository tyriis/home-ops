{pkgs, ...}:
{
  # services.xserver.enable = false;
  programs.hyprland.enable = true;
  programs.hyprland.xwayland.enable = true;

  # Enable Display Manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h | %F' --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  environment.systemPackages = with pkgs; [
    greetd.tuigreet
    pyprland
    hyprpicker
    hyprcursor
    hyprlock
    hypridle
    hyprpaper

    wezterm
    cool-retro-term

    starship
    helix

    qutebrowser
    zathura
    mpv
    imv
    kitty
    waybar

    networkmanagerapplet
    bibata-cursors

    # gnome.nautilus
    xfce.thunar
    tela-icon-theme
    tela-circle-icon-theme

  ];

  # https://nixos.wiki/wiki/Hyprland
  # security.polkit.enable = true;
  # security.polkit.extraConfig = ''
  #   polkit.addRule(function(action, subject) {
  #     if (
  #       subject.isInGroup("users")
  #         && (
  #           action.id == "org.freedesktop.login1.reboot" ||
  #           action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
  #           action.id == "org.freedesktop.login1.power-off" ||
  #           action.id == "org.freedesktop.login1.power-off-multiple-sessions"
  #         )
  #       )
  #     {
  #       return polkit.Result.YES;
  #     }
  #   });
  # '';
}
