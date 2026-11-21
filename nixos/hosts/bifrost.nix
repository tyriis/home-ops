# bifrost — NUC 14 Essential docker-lane host (#11420 rebuild, 2026-11-19).
# Carries the SAME 256 GB WD SN720 that proved every boot mechanic as
# bifrostix on the NUC7i5: the disk is the system, the chassis is a
# peripheral. At cutover this host inherits the name, the address, and
# the workloads of the decommissioned Lightwhale bifrost, and bifrostix
# retires as a separate host.
{
  imports = [ ./hardware-bifrost.nix ./bifrost-fs.nix ];

  networking.hostName = "bifrost";

  # Addressing: DHCP, no host-static block. One addressing source per
  # link, and it is the network — proven the hard way as bifrostix with
  # .180/.231 on one NIC (2026-11-16: kernel answers probes for the
  # static address from the lease source; the static is unreachable).
  # Target state: controller entry "bifrost", fixed 192.168.100.10, the
  # address the decommissioned Lightwhale host releases at cutover.
  # Until then: unreserved DHCP; identity is the machine-id below, and
  # the reservation keys to its DUID.

  # MAC-name the NIC only once the NUC14's MAC is known — read it at
  # the first physical boot and fill this in (pattern of
  # ./bifrostix.nix:10-eno1-name). Predictable naming is fine until
  # then; nothing on this host addresses the interface by name yet.
  # systemd.network.links."10-eno1-name" = {
  #   matchConfig.MACAddress = "<fill at first physical boot>";
  #   linkConfig.Name = "eno1";
  # };

  # The initrd SSH escape lane (docker-lane baseline) needs the NIC
  # driver present in stage 1 — a driverless initrd has no link, no
  # DHCP, no 2222 (bifrostix: e1000e, proven by the 2026-11-16 drill).
  # NUC 14 Essential's 2.5GbE is a Realtek RTL8125D/BG-CG (ASUS spec,
  # verified 2026-11-19) — r8169, not igc: no Intel NIC on this board.
  # Firmware ships: hardware.enableRedistributableFirmware is NixOS-on
  # and linux-firmware carries rtl_nic/rtl8125*.
  boot.initrd.kernelModules = [ "r8169" ];

  # Not 26.11: this host continues the bifrostix disk and inherits its
  # @persistent/var-lib-nixos uid state. stateVersion describes the
  # system's origin, not the chassis.
  system.stateVersion = "26.05";
}
