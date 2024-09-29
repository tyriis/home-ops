{ inputs, config, lib, pkgs, ... }:
{
  # https://wiki.nixos.org/wiki/Syncthing
  services = {
    syncthing = {
      enable = true;
      user = "nils";
      dataDir = "/home/nils/syncthing";
      configDir = "/home/nils/.config/syncthing";
      overrideDevices = true;     # overrides any devices added or deleted through the WebUI
      # overrideFolders = true;     # overrides any folders added or deleted through the WebUI
      settings = {
        devices = {
          "talos-flux" = { id = "4QNOCIW-TF53CIE-JTVRRHD-CMMC4LI-QEXUUP3-EQM5UI5-HR5FWS2-HDTDZAM"; };
          # "device2" = { id = "DEVICE-ID-GOES-HERE"; };
        };
        # folders = {
        #   "tyriis-obsidian-notes" = {         # Name of folder in Syncthing, also the folder ID
        #     path = "/home/myusername/Documents";    # Which folder to add to Syncthing
        #     devices = [ "device1" "device2" ];      # Which devices to share the folder with
        #   };
        #   "Example" = {
        #     path = "/home/myusername/Example";
        #     devices = [ "device1" ];
        #     ignorePerms = false;  # By default, Syncthing doesn't sync file permissions. This line enables it for this folder.
        #   };
        # };
      };
    };
  };

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true"; # Don't create default ~/Sync folder

  # Syncthing ports: 8384 for remote access to GUI
  # 22000 TCP and/or UDP for sync traffic
  # 21027/UDP for discovery
  # source: https://docs.syncthing.net/users/firewall.html
  networking.firewall.allowedTCPPorts = [ /* 8384 */ 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];
}
