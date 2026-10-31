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

## Monitoring

Metrics v3 is served on the S3 API listener (`9000`), not the console: `GET /minio/metrics/v3`. The v2
paths (`/minio/v2/metrics/{cluster,node,bucket,resource}`) still answer but are unused here — one v3
scrape replaces the v2 cluster+node+resource trio, and the Console speaks v3. Each host's vmagent
scrapes it as job `minio`, using the token below.

`MINIO_PROMETHEUS_AUTH_TYPE` stays at its default `jwt`; `public` is not used because it serves bucket
names, sizes and object counts unauthenticated. No `MINIO_PROMETHEUS_*` key belongs in this `sops.env`.

The endpoint authorises the token: `admin:Prometheus` is the exact least-privilege action, and the
built-in `readonly` policy is not enough (403). Per host, open a shell in that host's container
(`docker exec -it minio sh`; `mc` is the image's alias for `mcli`) and run:

```sh
mc alias set admin http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc admin user add admin prometheus <secret>
printf '%s' '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["admin:Prometheus"],"Resource":["arn:aws:s3:::*"]}]}' > /tmp/p.json
mc admin policy create admin prometheus-scrape /tmp/p.json
mc admin policy attach admin prometheus-scrape --user prometheus
mc alias set scrape http://127.0.0.1:9000 prometheus <secret>
mc admin prometheus generate scrape --api-version v3
```

The generated block keeps `job_name: minio-job` and `scheme: http`; take only its `bearer_token` — our
job is `minio`. That token is signed with the user's secret and expires in ~100 years, so it is a filed
credential: rotating the secret silently breaks the scrape.

Put it in the **vmagent** env as `MINIO_METRICS_TOKEN` in `docker/<host>/vmagent/sops.env`. This manual
step runs on the owning host, which holds the age key — `sops docker/<host>/vmagent/sops.env`, add the
key, save — then doco-cd redeploys vmagent; until then the job reports `up == 0` (403). Verify in the
central store with `up{job="minio"}` and `count by (host) ({__name__=~"minio_.*"})`; series carry `host`
and no `cluster`.

The Console Metrics page needs a read path into the central store and host tokens are write-only, so
console wiring is out of scope.

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

Key names stay readable without decrypting (`grep -oE '^MINIO_[A-Z_]+' docker/truenas/minio/sops.env`); only
the values are encrypted. Decryption itself works only on the owning host, or wherever that host's age private
key is present. The key is not in this repository, so a run elsewhere fails with
`identity did not match any of the recipients`.

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
