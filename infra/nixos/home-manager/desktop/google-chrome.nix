{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unstable.google-chrome
  ];
}
