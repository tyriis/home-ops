# InfluxDB 3 Enterprise (main cluster)

Long-term store for Home Assistant sensor history, running as a single pod in its own `influxdb`
namespace on the main cluster. The engine runs with a local `file` object store, so the dataset —
WAL, Parquet files and catalogue — lives on the `influxdb3-data` volume, and MinIO holds only the
restic backups of that volume. Home Assistant pushes over the InfluxDB integration and Grafana reads
with SQL over FlightSQL. Home Assistant's recorder and Prometheus are untouched — this is a third,
parallel path.
See [ADR 0021](../../../../../docs/decisions/0021-influxdb3-enterprise-ha-sensor-storage.md).

- app: `kubernetes/main/apps/influxdb/influxdb3/app/` (bjw-s app-template `5.3.0`, image
  `docker.io/library/influxdb:3.12.2-enterprise`)
- service: `influxdb3.influxdb.svc.cluster.local:8181`, ClusterIP only
- secrets: OpenBao `infra/kubernetes/main/influxdb/influxdb3` → Secret `influxdb3-env`
- storage: PVC `influxdb3-data`, 20 Gi `ceph-block`, created by the volsync component — this volume
  is the dataset, mounted at `--data-dir`
- backups: restic to MinIO daily at 03:30 — off the cluster-wide 2-hourly volsync slot — retaining
  daily 7 / weekly 4 / monthly 3
- Grafana: datasource `influxdb`, dashboard "Home Assistant (InfluxDB 3)"

The engine runs `--object-store=file --data-dir=/var/lib/influxdb3/data`. WAL, compacted Parquet and
the catalogue all live under that directory, and the license record is written there too, so the
volume is both the working set and the durable copy.

## Prerequisites

Hand-run once, in this order. Nothing here is in GitOps.

### 1. Backup repository

The volume is backed up by the repo's volsync component (restic to MinIO), which needs a repository of
its own before the app is deployed:

- MinIO user: add a dedicated user for the restic repository to `data/users` in `terraform-minio`, open a
  PR and let Atlantis apply it.
- OpenBao: create `infra/kubernetes/main/volsync/influxdb3-data` with the keys the component expects, the
  way [`docs/backstage/components/volsync/docs/index.md`](../../../../../docs/backstage/components/volsync/docs/index.md)
  describes:

| Key                     | Value                                                                  |
| ----------------------- | ---------------------------------------------------------------------- |
| `RESTIC_REPOSITORY`     | `s3:https://s3.techtales.io/<bucket>`                                  |
| `RESTIC_PASSWORD`       | freshly generated 64-character restic password                         |
| `AWS_ACCESS_KEY_ID`     | access key of that MinIO user, from `infra/minio/iam/nas.techtales.io` |
| `AWS_SECRET_ACCESS_KEY` | its secret                                                             |

### 2. OpenBao

Put the values at `infra/kubernetes/main/influxdb/influxdb3`:

| Key             | Value                                       |
| --------------- | ------------------------------------------- |
| `LICENSE_EMAIL` | mailbox that receives the verification link |
| `ADMIN_TOKEN`   | an `apiv3_...` token, generated offline     |
| `READ_TOKEN`    | added in step 4, once the pod is running    |

Generate the admin token with `openssl rand -base64 32` — InfluxDB 3 accepts a hand-written token
file, so no first-boot bootstrap is needed.

The ExternalSecret templates these into the environment the server reads: `INFLUXDB3_LICENSE_TYPE` is
fixed to `home`, `INFLUXDB3_LICENSE_EMAIL` comes from `LICENSE_EMAIL`, and `ADMIN_TOKEN` is rendered
into the `admin-token.json` file that `--admin-token-file` points at. `bao kv put` creates the path;
`bao kv patch` fails on a path that does not exist yet.

### 3. Verify the license

Once the pod is `Running`, InfluxData mails a verification link to `LICENSE_EMAIL`. Click it. The
license is stored in the data volume, not in the pod, so a rebuild does not need a second
verification. A lost volume does not need one either: the engine asks the license server for the
existing license for `LICENSE_EMAIL`, so keep that mailbox reachable — it is the recovery key, not a
repeat signup step.

### 4. Database and tokens

Exec into the running pod and create the database plus one read token for Grafana and one write
token for Home Assistant:

```sh
ADMIN=$(kubectl -n influxdb exec deploy/influxdb3 -- cat /etc/influxdb3/admin-token.json | jq -r .token)

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create database home_assistant --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --permission "db:home_assistant:read" --name grafana --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --permission "db:home_assistant:write" --name home-assistant --token "$ADMIN"
```

The token comes from the mounted `admin-token.json`, not from an `ADMIN_TOKEN` env key: the
ExternalSecret renders the JSON document as that file.

Add the read token to the same OpenBao entry as `READ_TOKEN`. The ExternalSecret `influxdb3-env`
feeds the app, and Grafana's `influxdb3-grafana-token` reads the same key for its datasource, so a
rotation is one `bao kv patch` plus an ESO refresh on both sides.

## Sizing

20 Gi holds years of Home Assistant sensor data at home cardinality; the engine compresses to
Parquet and keeps 7 daily, 4 weekly and 3 monthly snapshots in the restic repository. To grow the
volume, raise `VOLSYNC_CAPACITY` in `flux-sync.yaml` and reconcile — `ceph-block` expands online.

## Home Assistant

UI only, not GitOps — HA's configuration lives on its PVC.

Settings > Devices & Services > Add Integration > InfluxDB:

- API version: 2
- URL: `http://influxdb3.influxdb.svc.cluster.local:8181`
- bucket/database: `home_assistant`
- organisation: anything — InfluxDB 3 ignores it
- token: the `home-assistant` write token
- verify SSL: off

The recorder stays as-is; the integration writes in parallel. Entity allow/deny lists come later.

The database is `home_assistant`, but the **table** name is the measurement: HA writes one table per
unit (`°C`, `%`, `W`) or the entity id when there is no unit — `measurement_attr` defaults to
`unit_of_measurement` — and tags each row with the `entity_id` (`object_id` form, e.g.
`multi_sensor_battery_level`). Queries below therefore use a `<measurement>` placeholder.

## Grafana

The `influxdb` datasource is provisioned from GitOps (`kubernetes/main/apps/observability/grafana/instance/datasource.yaml`),
and the dashboard "Home Assistant (InfluxDB 3)" from
`kubernetes/main/apps/observability/grafana/observability/`. The dashboard picks the table from a
`measurement` variable and the entity from the rows of that table. The variable queries
`information_schema.tables` for `table_schema = 'iox'` and drops `system%`, because `SHOW TABLES`
returns `table_catalog` first and lists the system tables alongside the data tables. The datasource
queries with `version: SQL` over FlightSQL, so the plain-HTTP in-cluster URL needs
`insecureGrpc: true`.

## Retention

Unbounded. There are no retention policies; old data is deleted per table with SQL:

```sql
DELETE FROM "<measurement>" WHERE time < '2026-01-01T00:00:00Z';
```

## Restore

The volume holds the whole dataset, so a restore is a real recovery. `influxdb3-data` carries a
`dataSourceRef` to `ReplicationDestination/influxdb3-data`, so the claim is populated by the volsync
volume populator **when it is created**. A restore therefore recycles the claim instead of writing
into the running volume:

```sh
# 1. restore the newest restic snapshot into a fresh volume image
kubectl -n influxdb patch replicationdestination influxdb3-data --type=merge \
  -p '{"spec":{"trigger":{"manual":"restore-2026-01-01"}}}'

# 2. wait until status.lastManualSync holds that marker and status.latestImage is set
kubectl -n influxdb get replicationdestination influxdb3-data \
  -o jsonpath='{.status.lastManualSync}{" "}{status.latestImage.name}{"\n"}'

# 3. drop the old claim so the populator can rebuild it from that image
kubectl -n influxdb scale deploy/influxdb3 --replicas=0
kubectl -n influxdb delete pvc influxdb3-data
flux reconcile kustomization influxdb3

# 4. once the claim is Bound again
kubectl -n influxdb scale deploy/influxdb3 --replicas=1
```

Any `spec.trigger.manual` value the operator has not seen before starts a restore; the value is only a
marker, so pick the date of the restore attempt.

The snapshot is taken through a Ceph volume snapshot, so the restored directory is consistent as of
that instant and the WAL under it replays on start. Data written after the snapshot is lost.

## Verify

```sh
kubectl -n influxdb get pods
kubectl -n influxdb logs deploy/influxdb3
kubectl -n influxdb exec deploy/influxdb3 -- du -sh /var/lib/influxdb3/data
kubectl -n influxdb port-forward svc/influxdb3 8181:8181 &
curl -fsS http://127.0.0.1:8181/health
curl -fsS http://127.0.0.1:8181/metrics | head
```

After Home Assistant has been writing for a few minutes, the row count comes from a SQL query in
Grafana's Explore (datasource `influxdb`), against one of the unit tables:

```sql
SELECT count(*) FROM "<measurement>";
```

A pod that is `Running` but holds no data usually means the engine is not writing to the mounted
volume, or the claim was restored from an empty repository. The pod log carries the failure; the
readiness check only reports `/health`.
