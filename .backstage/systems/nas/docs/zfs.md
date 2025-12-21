# ZFS Setup

<https://github.com/siderolabs/extensions/blob/main/storage/zfs/README.md>

```console
kubectl -n kube-system debug -it --profile sysadmin --image=alpine node/nas02
```

To verify AES‑GCM support on your Talos node:acltype

```console
cat /proc/crypto | grep gcm
```

```console
name : gcm(aes)
driver : generic-gcm-aesni-avx
```

```console
apk add zfs openssl
```

```console
lsmod | grep zfs
```

```console
zfs 6701056 0
spl 131072 1 zfs
```

```console
mkdir -p /host/var/mnt/pool
```

```console
ln -s /host/var/lib/zfs /var/lib/zfs
```

```console
openssl rand -hex 32 > /host/var/lib/zfs/encryption.key
```

store in [secrets.techtales.io/](https://secrets.techtales.io/ui/vault/secrets/infra/show/techtales/kube-nas)

```console
chmod 600 /host/var/lib/zfs/encryption.key
```

```console
chroot /host zpool create -f \
  -o ashift=12 \
  -O acltype=posixacl \
  -O compression=lz4 \
  -O dnodesize=auto \
  -O normalization=formD \
  -O relatime=off \
  -O xattr=sa \
  -O encryption=aes-256-gcm \
  -O keylocation=file:///var/lib/zfs/encryption.key \
  -O keyformat=hex \
  -O mountpoint="legacy" \
  pool0 mirror /dev/sda /dev/sdb
```

```console
chroot /host zpool status
```

```console
pool  : zfs-pool
state : ONLINE
config:

  NAME        STATE     READ WRITE CKSUM
  zfs-pool    ONLINE       0     0     0
  mirror-0    ONLINE       0     0     0
  sda         ONLINE       0     0     0
  sdb         ONLINE       0     0     0

errors: No known data errors
```

## create named datasets

create an openebs zfsvolume
