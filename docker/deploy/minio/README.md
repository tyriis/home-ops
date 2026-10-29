# minio

S3-compatible object store for the clusters, running the `pgsty/silo` image.
This directory holds the shared compose template; each host runs its own instance against a local
data path.

## Layout

- `docker/deploy/minio/compose.yaml`: shared compose definition (image, ports, healthcheck, `SOPS_ENV_FILE`, default `sops.env`)
- `docker/synology/minio/compose.yaml`: synology include shim (`project_directory: .`) plus the json-file logging labels VictoriaLogs needs
- `docker/synology/minio/.env`: `TARGET=synology`, `DATA_PATH=/volume1/minio/data`, `USER_ID=1026`, `GROUP_ID=100`
- `docker/synology/minio/sops.env`: synology encrypted dotenv
- `docker/truenas/minio/compose.yaml`: truenas include shim, identical to the synology one
- `docker/truenas/minio/.env`: `TARGET=truenas`, `DATA_PATH=/mnt/tank/minio`, `USER_ID=3000`, `GROUP_ID=3000`
- `docker/truenas/minio/sops.env`: truenas encrypted dotenv
- `docker/.doco-cd.synology.yaml` and `docker/.doco-cd.truenas.yaml`: doco-cd registration per host

## Ports

- `9000`: S3 API, published on all interfaces (`API_PORT` overrides).
- `9001`: console, published on all interfaces (`CONSOLE_PORT` overrides).

TLS terminates in front of the host: nginx-proxy-manager on the NAS serves `s3.techtales.io` (API)
and `minio.techtales.io` (console); the Synology DSM reverse proxy serves the
`*.synology.techtales.io` equivalents. A proxy target change on either host must keep the
published ports in step.

## Env split

Two files per host, with different reach:

- `.env` is interpolation only. doco-cd hands it to compose, never to the container. It sets `TARGET`, `DATA_PATH`, `USER_ID` and `GROUP_ID`.
- `sops.env` reaches the container through the template's `env_file:`. Both hosts set `MINIO_ROOT_USER`,
  `MINIO_ROOT_PASSWORD` (minimum 8 characters) and `MINIO_BROWSER_REDIRECT_URL` (console redirect
  target after login). truenas adds `MINIO_SERVER_URL` (base URL for presigned URLs); synology also
  sets `MINIO_STORAGE_CLASS_RRS`, `MINIO_STORAGE_CLASS_STANDARD` and `MINIO_UPDATE`.

`sops.env` is age-encrypted per host recipient as declared in `.sops.yaml`; `.env` stays plaintext
and carries no secret.

## Manual decrypt check

```bash
sops --decrypt docker/truenas/minio/sops.env
```

## Runtime requirement on doco-cd host

- `doco-cd` must hold that host's age private key, via `SOPS_AGE_KEY_FILE` (recommended).
- `DATA_PATH` must be owned by `USER_ID:GROUP_ID`. The container runs as that user with `cap_drop: [ALL]` and `no-new-privileges`.

## Consumers

volsync restic, CNPG barman-cloud (main cluster, immich, forgejo), pocket-id litestream, the Atlantis
state backend and the terraform-minio provider all read this endpoint. The bucket keys live in the
data directory, so they survive a supervisor or image change; the endpoints must not.

## Notes

- The image is digest-pinned and bumped by Renovate through the shared `pgsty/silo` preset.
- One instance per data path. Single-drive mode has no cross-process locking: a second server writing
  the same directory corrupts `.minio.sys` and bucket metadata. Sharing storage between instances
  requires distributed mode, never two containers on one bind mount.
- A large version jump can perform a one-way storage-format upgrade. Take an off-box copy of
  `DATA_PATH` before such a bump: once the new version writes, the previous image cannot read the data.
- The `apps` network is declared by several stacks per host, so compose logs
  `a network with name apps exists but was not created for project "minio"`. Expected, not an error.
