{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # discord
    # screensharing not working on wayland, workaround
    vesktop
  ];
}
