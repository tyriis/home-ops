{ pkgs, ... }:
{
  home.packages = with pkgs; [
    unstable.vscode
  ];
}
