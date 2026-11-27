# NUC 14 Essential (NUC14MNK, Intel TWL-N250) — hardware facts for the
# successor board. Hand-owned, mirroring hardware-bifrostix.nix's role;
# unlike that file it is not generate-config output, so everything here
# is deliberate and none of it is a "do not modify" promise.
#
# Storage identity is UNCHANGED from the NUC7i5: the SN720 disk with
# UUID 4e2aa3de… physically moved (#11420 rebuild, 2026-11-19), so the
# mounts below are the same disk, same subvolumes, same ESP.
{ config, lib, ... }:

{
  # Stage-1 storage/input surface for this board. ahci stays declared
  # though no boot device needs it: slot 2 is an M.2 2242 SATA
  # (ASUS spec, 2026-11-19) — an initrd that can read that disk keeps
  # the 16 GB vendor-OS copy reachable from the rescue shell.
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/4e2aa3de-4b26-4a84-bde5-13465a488466";
      fsType = "btrfs";
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/4e2aa3de-4b26-4a84-bde5-13465a488466";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/4e2aa3de-4b26-4a84-bde5-13465a488466";
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/8DF6-F3FC";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
