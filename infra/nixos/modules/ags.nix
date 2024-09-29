{pkgs, ...}:
{
  environment.systemPackages = with pkgs; [
    ags
    gnome.adwaita-icon-theme

    gtksourceview
    webkitgtk
    accountsservice
  ];
  nixpkgs.overlays = [
    (final: prev: {
      ags = prev.ags.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ pkgs.libdbusmenu-gtk3 pkgs.gtk3 ];
      });
    })
  ];
  services.upower.enable = true;

}
