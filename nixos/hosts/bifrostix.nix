# bifrostix — NUC7i5 docker-lane pilot host (#11792).
{
  imports = [ ./hardware-bifrostix.nix ];

  networking.hostName = "bifrostix";

  # Name the NIC by MAC: vendor-fleet-style name (eno1) with no BIOS-name
  # dependency and no hand-written .link on the host. Without this,
  # predictable naming names the NIC enp0s31f6 (e1000e on NUC7).
  systemd.network.links."10-eno1-name" = {
    matchConfig.MACAddress = "94:c6:91:19:a5:16";
    linkConfig.Name = "eno1";
  };

  # Addressing: 192.168.30.180 is a host-static outside the gateway pool
  # (WORKSTATIONS/VLAN 30 pool = 192.168.30.200-.254, 24 h lease).
  # Pool addresses move on reboot — the 2026-11-16 switch lease moved
  # .232 to .231 — so a pool address can never be this host's
  # reachable-address guarantee. 180 is never pool-assigned: verified
  # free by ping + ARP 2026-11-16.
  #
  # DHCP stays enabled for DNS (lease serves the VLAN 30 resolver
  # 192.168.30.1) and for a fallback route. The config-guaranteed route
  # (metric 50) always beats the DHCP route (metric 1024 at this pin —
  # verified live). Gateway 192.168.30.1 verified by live traffic: the
  # 2026-11-16 switch downloads routed through it.
  systemd.network.networks."10-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "yes";
    address = [ "192.168.30.180/24" ];
    routes = [ { Gateway = "192.168.30.1"; Metric = 50; } ];
  };

  system.stateVersion = "26.05";
}
