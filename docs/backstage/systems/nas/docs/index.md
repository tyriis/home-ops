# System: nas

The `nas` system is an experimental TrueNAS deployment running on Talos Linux nodes (`nas01`, `nas02`).

## What it provides

- **NFS shares** served to the Kubernetes clusters and consumed via the `csi-driver-nfs` CSI driver.
- **ZFS storage** on `nas02`, including an encrypted (AES-256-GCM) mirrored pool with named datasets used by OpenEBS ZFS volumes.
- **doco-cd workloads** deployed from this repository.
- **MinIO** as an S3-compatible object store, used as a VolSync replication target.

## Documentation

- [Installation](installation.md) — bootstrapping the Talos nodes and cluster setup.
- [NFS Server](nfs-server.md) — preparing the disk and exporting NFS shares.
- [ZFS](zfs.md) — ZFS pool setup, encryption, and disaster recovery on `nas02`.
