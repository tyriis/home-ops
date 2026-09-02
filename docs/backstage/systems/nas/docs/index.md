# System: nas

The `nas` system is a dedicated TrueNAS storage server (AOSTAR WTR Pro — Intel N100, 32 GB RAM, 250 GB NVMe OS disk, 4x 8 TB HDD data pool).

## What it provides

- **NFS shares** served to the Kubernetes clusters and consumed via the `csi-driver-nfs` CSI driver.
- **ZFS storage** with encrypted (AES-256-GCM) mirrored pool and named datasets.
- **MinIO** as an S3-compatible object store, used as a VolSync replication target.
- **doco-cd workloads** deployed from this repository.

## Documentation

- [Installation](installation.md) — historical install notes from the predecessor `nas01`/`nas02` deployment.
- [NFS Server](nfs-server.md) — preparing the disk and exporting NFS shares.
- [ZFS](zfs.md) — ZFS pool setup, encryption, and disaster recovery.
