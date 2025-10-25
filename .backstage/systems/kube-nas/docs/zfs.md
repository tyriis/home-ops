# ZFS Setup

<https://github.com/siderolabs/extensions/blob/main/storage/zfs/README.md>

kubectl -n kube-system debug -it --profile sysadmin --image=alpine node/nas01

To verify AES‑GCM support on your Talos node:acltype

/ # cat /proc/crypto | grep gcm
name : gcm(aes)
driver : generic-gcm-aesni-avx

/ # apk add zfs openssl

/ # lsmod | grep zfs
zfs 6701056 0
spl 131072 1 zfs

/ # mkdir -p /host/var/lib/zfs
/ # ln -s /host/var/lib/zfs /var/lib/zfs
/ # openssl rand -hex 32 > /var/lib/zfs/encryption.key

store in [secrets.techtales.io/](https://secrets.techtales.io/ui/vault/secrets/infra/show/techtales/kube-nas)

/ # chmod 600 /var/lib/zfs/encryption.key

/ # chroot /host zpool create -m legacy -o ashift=12 -O acltype=posixacl -O compression=lz4 \
 -O dnodesize=auto -O normalization=formD -O relatime=off -O xattr=sa \
 -O encryption=aes-256-gcm -O keylocation=file:///var/lib/zfs/encryption.key -O keyformat=hex \
 -O mountpoint=/var/mnt/zfs-pool zfs-pool mirror /dev/sda /dev/sdb

/ # chroot /host zpool status
pool: zfs-pool
state: ONLINE
config:

        NAME        STATE     READ WRITE CKSUM
        zfs-pool    ONLINE       0     0     0
          mirror-0  ONLINE       0     0     0
            sda     ONLINE       0     0     0
            sdb     ONLINE       0     0     0

errors: No known data errors
