{pkgs, ...}:
{
  # services.xserver.enable = false;
  programs.hyprland.enable = true;

  # Enable Display Manager
  services.greetd = {
    enable = true;
    settings = {
      terminal = {
        # switch to tty2 to prevent systemd spam
        vt = 3;
      };
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet -g \"Greetings, Time Traveler! ⏳ You've arrived at the intersection of imagination and reality. What wonders will you create today?\" w--time --time-format '%I:%M %p | %a • %h | %F' --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  environment.systemPackages = with pkgs; [

    wayland
    xdg-desktop-portal-hyprland
    libsForQt5.qt5.qtwayland


    greetd.tuigreet
    pyprland # need evaluation
    hyprpicker # does not work currently
    hyprcursor

    hyprlock
    hypridle
    hyprpaper

    kitty # could be in home manager?

    networkmanagerapplet
    bibata-cursors # should be in home manager

    tela-icon-theme # should be in home manager, are they used?
    tela-circle-icon-theme # should be in home manager, are they used?

  ];

  # https://nixos.wiki/wiki/Hyprland
  security.polkit.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        subject.isInGroup("users")
          && (
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions"
          )
        )
      {
        return polkit.Result.YES;
      }
    });
  '';
}
