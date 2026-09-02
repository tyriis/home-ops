# System: synology

The `synology` system is a Synology DS218+ NAS running DSM.

## What it provides

- **doco-cd workloads** deployed from this repository via Container Manager (Docker Compose).
- **ACME certificates** for `synology.techtales.io` and `*.synology.techtales.io`, issued and renewed via the DNS-01 challenge using Cloudflare.
- **Reverse proxy** exposing services such as MinIO (`minio.synology.techtales.io`, `s3.synology.techtales.io`).
- **Storage** with a RAID 1 BTRFS storage pool.

## Documentation

- [Setup](setup.md) — step-by-step setup of the NAS.
- [ACME DNS-01 Challenge](acme-dns01.md) — certificate issuance and renewal.
