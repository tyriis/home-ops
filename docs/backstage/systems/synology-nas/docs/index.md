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

## Log shipping

Host and container logs are shipped to the central VictoriaLogs platform
(`https://logs.techtales.io`) by a `victoria-logs-collector` (vlagent) stack
deployed via doco-cd from `docker/synology/victoria-logs-collector`.

- Mounts `/var/log` (read-only) plus the Container Manager data root
  (`/volume1/@docker/containers`) and globs the DSM text logs
  (`messages`, `*.log`, `samba/*.log`, `nginx/*.log`, `systemd/*.log`,
  `packages/*.log`) and container `*-json.log` files.
- Authenticates with the vmauth `synology` unit token (`VL_TOKEN` in `sops.env`).
- Synology's Container Manager defaults to the `db` logging driver (SQLite,
  not shippable); services we ship set `logging: driver: json-file` in their
  compose files so their stdout lands in `*-json.log`.
