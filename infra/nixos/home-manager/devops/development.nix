{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # google zx scripting library for node
    nodePackages.zx
    # load .envrc files in folder tree
    direnv
    # mise a modern development environment manager
    mise
  ];
}
