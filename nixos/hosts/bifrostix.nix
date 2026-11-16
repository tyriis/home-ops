# bifrostix — NUC7i5 docker-lane pilot host (#11792).
{
  imports = [ ./hardware-bifrostix.nix ];

  networking.hostName = "bifrostix";

  # Single addressing source: the 10-eno1 unit below, nothing else.
  # NixOS's default per-interface DHCP unit (99-ethernet-default-dhcp)
  # is switched off — with a lease and a static address on one link the
  # kernel replies to static-address probes from the lease source
  # (proven live 2026-11-16: .180 unreachable beside .231).
  networking.useDHCP = false;

  # Name the NIC by MAC: vendor-fleet-style name (eno1) with no BIOS-name
  # dependency and no hand-written .link on the host. Without this,
  # predictable naming names the NIC enp0s31f6 (e1000e on NUC7).
  systemd.network.links."10-eno1-name" = {
    matchConfig.MACAddress = "94:c6:91:19:a5:16";
    linkConfig.Name = "eno1";
  };

  # Pure-static 192.168.30.180/24, host of record for the pilot.
  # Outside the WORKSTATIONS/VLAN 30 pool (30.200-30.254, 24 h lease):
  # pool addresses move on reboot (.232 to .231 on 2026-11-16), so a
  # pool address is never a reachable-address guarantee. 180 verified
  # free by ping + ARP 2026-11-16. Gateway and DNS are the VLAN 30
  # router 192.168.30.1 — the same values the DHCP lease served and
  # every download of the 2026-11-16 switch session routed through.
  systemd.network.networks."10-eno1" = {
    matchConfig.Name = "eno1";
    address = [ "192.168.30.180/24" ];
    routes = [ { Gateway = "192.168.30.1"; Metric = 50; } ];
    networkConfig.DNS = "192.168.30.1";
  };

  system.stateVersion = "26.05";
}
