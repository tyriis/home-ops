{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # wayland terminal emulator
    kitty
  ];
}
