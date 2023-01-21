# Talos

## preparation (see taskfile)

## Install

```console
talosctl apply-config --insecure \
    --nodes 192.168.1.51 \
    --file infra/talos/clusterconfig/talos-flux-talos01.yaml
```

## Raspberry Pi 4 fanshim issue

### Description

I use the Raspberry Pi fanshim. Unfortunately the Friction-fit header does not worked as expected and i got a few issues where smart fans have not worked as expected.
As i neeed the system to be reliable I decided to solder the header to the pi.

The LED connector is attached to the PI UART pin, what in my opinion is a bad product design decission. During boot there is crosstalk between UART and bootloader.
In the raspi os version the problem does not occur. I encountered it 1st when trying tro boot ubuntu but was not aware of the problem. At this point I have been to lazy to debug it further.

When trying to run talos the problem poped up again. And I dont wanted to accept it so I digged deeper into and finally figured out why u-boot creates some giberish messages instead of booting my system.

#### Part 1 U-boot

In order to prevent u-boot from being intercepted by uart inputs I followed this guide: <https://raspberrypi.stackexchange.com/a/117950> (i needed to install `openssl-dev` aswel)

This let me boot till grub where the crosstalk again intercepted the boot.

#### Part 2 GRUB

I did not achieved to disable uart in grub, instead i disabled uart in config.txt (located on the 1st partition) to prevent any uart on the device.

This also fixed the uboot crosstalk.

#### Part 0 config.txt

changing config txt after flashing

```console
➜ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
sda           8:0    1     0B  0 disk
sdb           8:16   1     0B  0 disk
sdc           8:32   1     0B  0 disk
sdd           8:48   0 111,8G  0 disk
├─sdd1        8:49   0   100M  0 part
├─sdd2        8:50   0     1M  0 part
├─sdd3        8:51   0  1000M  0 part
├─sdd4        8:52   0     1M  0 part
├─sdd5        8:53   0   100M  0 part
└─sdd6        8:54   0    42M  0 part
```

My device is attached to `sdd`.

```console
sudo mount /dev/sdd1 /mnt
```

I want to edit the file with vim (but you can use your favorite editor aswel.)
and change the line `enable_uart=1` to `enable_uart=0`

```console
sudo vim /mnt/config.txt
```

After applying the changes dont forget to save the file and unmount your device.

```console
sudo umount /mnt
```

Now you can remove the device and boot it on the pi :)
