# InfluxDB 3 Enterprise

Long-term store for Home Assistant sensor history on the main cluster. One pod in the `influxdb`
namespace, ClusterIP-only, with its whole dataset on the `influxdb3-data` Ceph block volume — the
engine runs a local `file` object store, and MinIO holds only the restic backups of that volume. Home
Assistant pushes state changes to it over the InfluxDB integration and Grafana reads it back with SQL
over FlightSQL. The HA recorder and Prometheus both stay as they are; this is a third, parallel path
beside them.

Decision record:
[ADR 0021](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0021-influxdb3-enterprise-ha-sensor-storage.md).

Source:
[`kubernetes/main/apps/influxdb/influxdb3/app/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/influxdb/influxdb3/app)
— bjw-s app-template `5.3.0`, image `docker.io/library/influxdb:3.12.2-enterprise`.

## Shape

| Item      | Value                                                                |
| --------- | -------------------------------------------------------------------- |
| Namespace | `influxdb`                                                           |
| Service   | `influxdb3.influxdb.svc.cluster.local:8181`, ClusterIP only          |
| Storage   | PVC `influxdb3-data`, 20 Gi `ceph-block`, `--object-store=file`      |
| Secrets   | OpenBao `infra/kubernetes/main/influxdb/influxdb3` → `influxdb3-env` |
| Backups   | restic to MinIO, daily 03:30, daily 7 / weekly 4 / monthly 3         |
| License   | Enterprise "home" tier, verified once by email, stored on the volume |
| Retention | Unbounded, no retention policy; delete with SQL                      |

WAL, compacted Parquet files, the catalogue and the license record all live under `--data-dir`, so
the volume is the dataset. Nothing outside the cluster reads it directly; MinIO is a backup target
only.

## Provisioning

Two hand-run prerequisites, neither of them GitOps: the restic repository (a dedicated MinIO user in
`terraform-minio`, plus its OpenBao entry) and the `apiv3_...` admin token generated offline with
`openssl rand -base64 32`. Both land in the OpenBao entries above. Once the pod is up, the database
and its two database-scoped tokens are created inside the pod:

```sh
ADMIN=$(kubectl -n influxdb exec deploy/influxdb3 -- cat /etc/influxdb3/admin-token.json | jq -r .token)

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create database home_assistant --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --permission "db:home_assistant:read" --name grafana --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --permission "db:home_assistant:write" --name home-assistant --token "$ADMIN"
```

A token string is printed once, at creation, and cannot be read back — `influxdb3 show tokens` lists
a truncated hash, never the value. Keep both in OpenBao: `READ_TOKEN` for Grafana and `WRITE_TOKEN`
for Home Assistant. Two consumers read `READ_TOKEN`: the app's own `ExternalSecret`, and
`influxdb3-grafana-token` in the Grafana app, which feeds the `influxdb` datasource. Rotating it is
one `bao kv patch` plus an ESO refresh on both sides.

The token is read from the mounted `admin-token.json`; the Secret carries no `ADMIN_TOKEN` key.

The license check is a first-boot step: InfluxData mails the verification link to `LICENSE_EMAIL`
once the pod is running, and clicking it produces a license bound to the cluster id and that
address. The record lands on the volume, so a rebuild does not need a second verification; a lost
volume re-fetches the existing license from the license server by address, which makes the mailbox
the recovery key rather than a repeat signup step.

## Home Assistant

UI only — HA's configuration lives on its PVC, so this is not in the repository. Settings > Devices &
Services > Add Integration > InfluxDB: API version 2, URL
`http://influxdb3.influxdb.svc.cluster.local:8181`, bucket/database `home_assistant`,
organisation anything (InfluxDB 3 ignores it), token = the `home-assistant` write token, verify SSL
off. The recorder keeps writing as before; entity allow/deny lists come later.

`home_assistant` is the database, not the table: with HA's default `measurement_attr:
unit_of_measurement` the measurement becomes the unit (`°C`, `%`, `W`) or the entity id where there
is no unit, and each row is tagged with the `entity_id` in `object_id` form. Queries below use a
`<measurement>` placeholder for that reason.

## Grafana

The `influxdb` datasource is provisioned from GitOps with `version: SQL` and `insecureGrpc: true`:
SQL runs over FlightSQL (gRPC), so the plain-HTTP in-cluster URL fails its handshake without that
flag. The dashboard "Home Assistant (InfluxDB 3)" ships beside it from
`kubernetes/main/apps/observability/grafana/observability/`, picking the table from a `measurement`
variable (`information_schema.tables`, schema `iox`, minus `system%`) and the entity from that
table's rows.

## Verify

```sh
kubectl -n influxdb get pods
kubectl -n influxdb logs deploy/influxdb3
kubectl -n influxdb exec deploy/influxdb3 -- du -sh /var/lib/influxdb3/data
kubectl -n influxdb port-forward svc/influxdb3 8181:8181 &
curl -fsS http://127.0.0.1:8181/health
curl -fsS http://127.0.0.1:8181/metrics | head
```

Then, after Home Assistant has been writing for a few minutes, from Grafana's Explore on the
`influxdb` datasource, against one of the unit tables:

```sql
SELECT count(*) FROM "<measurement>";
```

A `Running` pod that holds no data means the engine is not writing to the mounted volume, or the
claim came back from an empty repository; the pod log carries the failure, the readiness check does
not.

## Retention and deletion

No retention policies exist. Row deletion is a CLI operation, not SQL — `DELETE FROM` is not
supported by the 3.12 storage engine:

```sh
influxdb3 delete rows --database home_assistant --table "<measurement>" \
  --max-time 2026-01-01T00:00:00Z --token "$ADMIN"
```

`delete rows` needs `--table`. It deletes rows of one named table. To clear a whole database, run
`influxdb3 delete database --data-only` instead, never a loop over tables. `--max-time` is
exclusive, and `--all-time` spans every timestamp of that table. Deletes are asynchronous and
applied by the compactor, with a default minimum age of one day, so rows stay queryable until then.

To keep the database, its tokens and its caches while clearing the data, use
`influxdb3 delete database --data-only home_assistant`; add `--remove-tables` to drop the table
schemas as well. Running `delete database` **without** `--data-only` keeps the token rows by name but
kills their grants, and every client holding one starts receiving `401` until both tokens are
re-created.

## Backups

The `influxdb3-data` PVC comes from the `volsync` component, not from this app: the component builds
the claim, its restic `ReplicationSource` and the restore `ReplicationDestination`. The schedule is
overridden in the app's `kustomization.yaml` to a daily 03:30 run, because the component's default
(minute 0 of every even hour) collides with the fleet-wide volsync slot. Because the claim is created
against the `ReplicationDestination`, a restore recycles the claim rather than writing into the
running volume; the app README carries the step-by-step.

The restic repository is `s3:https://s3.techtales.io/volsync/main/influxdb/influxdb3-data` — the
shared `volsync` bucket with a prefix unique to this claim. The mover initialises it on the first
backup, so nothing is created by hand.

The volume is the source of truth, so the nightly snapshot is a full backup rather than a copy of
scratch space: it captures WAL, Parquet and catalogue at one instant, and the WAL replays on start.
Data written after the snapshot is lost, and the snapshot is taken through a Ceph volume snapshot, so
the restored directory is consistent as of that moment.
