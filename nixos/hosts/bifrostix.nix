# bifrostix — NUC7i5 docker-lane pilot host (#11792).
{
  imports = [ ./hardware-bifrostix.nix ];

  networking.hostName = "bifrostix";

  system.stateVersion = "26.05";
}
