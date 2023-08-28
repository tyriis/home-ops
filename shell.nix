let
  pkgs = import <nixpkgs> {};
in
  pkgs.mkShell {
    packages = [
      pkgs.age
      pkgs.direnv
      pkgs.go-task
      pkgs.k9s
      pkgs.kubectl
      pkgs.kubernetes-helm
      pkgs.pre-commit
      pkgs.sops
      pkgs.talosctl
      pkgs.terraform
      pkgs.terraform-docs
      pkgs.tig
      pkgs.tflint
      pkgs.tfsec
      (builtins.getFlake "github:budimanjojo/talhelper").packages.x86_64-linux.default
    ];
  }
