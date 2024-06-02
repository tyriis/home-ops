{ pkgs, config, ... }:

{

  users.defaultUserShell = pkgs.zsh;
  # Give extra permissions with Nix
  # nix.settings.trusted-users = [ "nils" ];

  # users.groups.nils = {
  #   gid = 1000;
  #   name = "nils";
  # };

  users.users.nils = {
    uid = 1000;
    isNormalUser = true;
    createHome = true;
    useDefaultShell = true;
    home = "/home/nils";
    extraGroups = [ "wheel" "networkmanager" "audio" "docker" ];
    openssh.authorizedKeys.keys =
      let
        authorizedKeys = pkgs.fetchurl {
          url = "https://github.com/tyriis.keys";
          sha256 = "pMt/WQcQJQ4vf0Z61rOc2u3jo5ylpmfK3Y5YKQyI4bU=";
        };
      in
      pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
  };

  users.users.jasmin = {
    isNormalUser = true;
    createHome = true;
    home = "/home/jasmin";
    extraGroups = [ "wheel" "networkmanager" "audio" "docker" ];
    openssh.authorizedKeys.keys =
      let
        authorizedKeys = pkgs.fetchurl {
          url = "https://github.com/jazzlyn.keys";
          sha256 = "5pYk7Rxc0IS3Ov7A5AVgqG5/DjjwiuCcp2jlY838/LM=";
        };
      in
      pkgs.lib.splitString "\n" (builtins.readFile
        authorizedKeys);
  };

  # allow of sudo without password
  # security.sudo.wheelNeedsPassword = false;
}
