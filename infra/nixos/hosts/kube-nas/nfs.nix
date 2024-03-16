# Edit this configuration file to manage nfs server.

{ config, pkgs, ... }:

{
  # Enable NFS server
  # https://nixos.wiki/wiki/NFS

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /export          192.168.1.20(rw,fsid=0,no_subtree_check)
    /export/data     192.168.1.20(rw,async,no_wdelay,nohide,no_subtree_check,insecure,all_squash,insecure_locks,sec=sys,anonuid=1000,anongid=100)
  '';
}
