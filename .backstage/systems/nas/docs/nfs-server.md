# NFS Server

## prepare system

<https://nixos.wiki/wiki/Btrfs>

Wipe existing partitions and create 1 partition on the disk `/dev/sda`

```bash
printf "label: gpt\n,,L\n" | sfdisk /dev/sda
```

Example output

```console
Checking that no-one is using this disk right now ... OK

Disk /dev/sda: 232,89 GiB, 250059350016 bytes, 488397168 sectors
Disk model: SSD 840 EVO 250G
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 33553920 bytes
Disklabel type: gpt
Disk identifier: DDF96D31-B1A5-4ADE-B8F4-6EF3FA0347BF

Old situation:

Device       Start       End   Sectors   Size Type
/dev/sda1     2048    206847    204800   100M EFI System
/dev/sda2   206848    208895      2048     1M BIOS boot
/dev/sda3   208896   2256895   2048000  1000M Linux filesystem
/dev/sda4  2256896   2258943      2048     1M Linux filesystem
/dev/sda5  2258944   2463743    204800   100M Linux filesystem
/dev/sda6  2463744 488396799 485933056 231,7G Linux filesystem

>>> Script header accepted.
>>> Created a new GPT disklabel (GUID: 0B7D82AE-7917-154C-9650-C61ADD1AF2BF).
/dev/sda1: Created a new partition 1 of type 'Linux filesystem' and of size 232,9 GiB.
Partition #1 contains a vfat signature.
/dev/sda2: Done.

New situation:
Disklabel type: gpt
Disk identifier: 0B7D82AE-7917-154C-9650-C61ADD1AF2BF

Device     Start       End   Sectors   Size Type
/dev/sda1   2048 488396799 488394752 232,9G Linux filesystem

The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

use the -f flag in case you have a previous filesystem

```bash
mkfs.btrfs -f /dev/sda1
```

Example output

```console
btrfs-progs v6.3
See https://btrfs.readthedocs.io for more information.

NOTE: several default settings have changed in version 5.15, please make sure
      this does not affect your deployments:
      - DUP for metadata (-m dup)
      - enabled no-holes (-O no-holes)
      - enabled free-space-tree (-R free-space-tree)

Label:              (null)
UUID:               c9c6ada9-b4c7-4369-970c-2b60f0169528
Node size:          16384
Sector size:        4096
Filesystem size:    232.88GiB
Block group profiles:
  Data:             single            8.00MiB
  Metadata:         DUP               1.00GiB
  System:           DUP               8.00MiB
SSD detected:       yes
Zoned device:       no
Incompat features:  extref, skinny-metadata, no-holes, free-space-tree
Runtime features:   free-space-tree
Checksum:           crc32c
Number of devices:  1
Devices:
   ID        SIZE  PATH
    1   232.88GiB  /dev/sda1
```

Create the btrfs subvolume

```bash
mkdir -p /mnt
mount /dev/sda1 /mnt
btrfs subvolume create /mnt/nfs
umount /mnt
```

Mount the partitions and subvolumes

```nix
# mount external disk
fileSystems."/mnt/volume1" = {
  device = "/dev/disk/by-uuid/c9c6ada9-b4c7-4369-970c-2b60f0169528";
  fsType = "btrfs";
  options = [ "subvol=nfs" "compress=zstd" "noatime" ];
};
```

Create export directory

```bash
mkdir /export
```
