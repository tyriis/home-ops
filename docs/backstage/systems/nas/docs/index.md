# System: nas

The `nas` system is a dedicated TrueNAS storage server (AOOSTAR WTR Pro — Intel N100, 32 GB RAM, 250 GB NVMe OS disk, 4× 8 TB HDD data pool).

## What it provides

- **NFS shares** served to the Kubernetes clusters and consumed via the `csi-driver-nfs` CSI driver.
- **ZFS storage** with encrypted (AES-256-GCM) mirrored pool and named datasets.
- **MinIO S3 endpoint** on the shared `pgsty/silo` image, run as a doco-cd compose stack instead of a TrueNAS middleware app; used as a VolSync replication target.
- **TLS** for `minio.techtales.io` / `s3.techtales.io` terminated by nginx-proxy-manager in front of the S3 endpoint.
- **doco-cd workloads** deployed from this repository.

## Documentation

- [Installation](installation.md) — historical install notes from the predecessor `nas01`/`nas02` deployment.
- [NFS Server](nfs-server.md) — preparing the disk and exporting NFS shares.
- [ZFS](zfs.md) — ZFS pool setup, encryption, and disaster recovery.
