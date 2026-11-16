# bifrostix — NUC7i5 docker-lane pilot host (#11792).
{
  imports = [ ./hardware-bifrostix.nix ];

  networking.hostName = "bifrostix";

  # Addressing: DHCP, no host-static block. The gateway holds a static
  # reservation for this NIC — controller entry "bifrostix", network
  # WORKSTATIONS (VLAN 30), fixed 192.168.30.31 (unifi
  # feat(clients): add bifrostix to workstations, 2026-11-16).
  # One addressing source per link, and it is the network: a
  # host-static beside a lease makes the static unreachable (kernel
  # replies to static-address probes from the lease source — proven
  # live 2026-11-16 with .180 and .231 on one NIC).
  #
  # Superseded the same day: host-static .180 + DHCP hybrid
  # (#11965/#11966, the dual-address defect) and pure host-static
  # (#11967) — the reservation is the address guarantee, held by the
  # controller where the fleet's addressing lives.

  # Name the NIC by MAC so the name survives kernel/driver changes
  # without a hand-written .link on the host. Predictable naming alone
  # would name the NIC enp0s31f6 (e1000e on NUC7).
  systemd.network.links."10-eno1-name" = {
    matchConfig.MACAddress = "94:c6:91:19:a5:16";
    linkConfig.Name = "eno1";
  };

  system.stateVersion = "26.05";
}
