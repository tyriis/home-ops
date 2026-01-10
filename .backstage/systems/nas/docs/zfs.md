# ZFS Setup nas02

<https://github.com/siderolabs/extensions/blob/main/storage/zfs/README.md>

test if zfs is working

```console
talosctl -n nas02 get extensions | grep zfs
```

should show something like

```console
NODE    NAMESPACE   TYPE              ID            VERSION   NAME          VERSION
nas02   runtime     ExtensionStatus   3             1         zfs           2.4.0-v1.12.0
```

```console
talosctl -n nas02 read /proc/modules | grep zfs
```

should show:

```console
zfs 6631424 7 - Live 0x0000000000000000 (PO)
spl 135168 1 zfs, Live 0x0000000000000000 (O)
```

To verify AES‑GCM support on your Talos node:acltype

```console
talosctl -n nas02 read /proc/crypto | grep gcm
```

should show:

```console
name         : rfc4106(gcm(aes))
driver       : rfc4106-gcm-aesni-avx
name         : gcm(aes)
driver       : generic-gcm-aesni-avx
name         : rfc4106(gcm(aes))
driver       : rfc4106-gcm-aesni
name         : gcm(aes)
driver       : generic-gcm-aesni
```

```console
kubectl -n kube-system debug -it --profile sysadmin --image=alpine node/nas02 && kubectl delete pods -n kube-system -l app.kubernetes.io/managed-by=kubectl-debug
```

```console
apk add openssl
```

```console
mkdir -p /host/var/mnt/pool
```

<!--
```console
ln -s /host/var/lib/zfs /var/lib/zfs
```
-->

```console
openssl rand -hex 32 > /host/var/lib/zfs/encryption.key
```

store in [secrets.techtales.io/](https://secrets.techtales.io/ui/vault/secrets/infra/show/techtales/nas/nas02)

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

> I needed to restart the node in order to make the zfsvolume work as expected in openebs

## create named datasets

create an openebs zfsvolume

## DR

### restore the encryption key

```terminal
echo "my-secret-key0123456789" > /host/var/lib/zfs/encryption.key
chmod 600 /host/var/lib/zfs/encryption.key
```

### check if the pool can be imported

```console
chroot /host zpool import
```

```console
  pool: glacier
    id: 17419615542118046973
 state: ONLINE
action: The pool can be imported using its name or numeric identifier.
config:

        glacier     ONLINE
          mirror-0  ONLINE
            sdb     ONLINE
            sda     ONLINE
```

### import the pool

```console
chroot /host zpool import -l glacier
```

```console
1 / 1 keys successfully loaded
```

### test

```console
chroot /host zpool status
```

```console
  pool: glacier
 state: ONLINE
  scan: resilvered 0B in 00:00:00 with 0 errors on Sat Dec 27 21:46:22 2025
config:

        NAME        STATE     READ WRITE CKSUM
        glacier     ONLINE       0     0     0
          mirror-0  ONLINE       0     0     0
            sdb     ONLINE       0     0     0
            sda     ONLINE       0     0     0

errors: No known data errors
```
