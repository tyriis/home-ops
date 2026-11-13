# InfluxDB 3 Enterprise (main cluster)

Long-term store for Home Assistant sensor history, running as a single pod in its own `influxdb`
namespace on the main cluster. Data lives in the TrueNAS MinIO bucket `influxdb3`, so the pod itself
keeps no state; Home Assistant pushes over the InfluxDB integration and Grafana reads with SQL over
FlightSQL. Home Assistant's recorder and Prometheus are untouched — this is a third, parallel path.
See [ADR 0021](../../../../../docs/decisions/0021-influxdb3-enterprise-ha-sensor-storage.md).

- app: `kubernetes/main/apps/influxdb/influxdb3/app/` (bjw-s app-template `5.3.0`, image
  `docker.io/library/influxdb:3.12.2-enterprise`)
- service: `influxdb3-app.influxdb.svc.cluster.local:8181`, ClusterIP only
- secrets: OpenBao `infra/kubernetes/main/influxdb/influxdb3` → Secret `influxdb3-env`
- Grafana: datasource `influxdb`, dashboard "Home Assistant (InfluxDB 3)"

## Prerequisites

Hand-run once, in this order. Nothing here is in GitOps.

### 1. MinIO bucket and user

On the TrueNAS MinIO instance (`docker exec -it minio sh`; `mc` is the image's alias for `mcli`):

```sh
mc alias set admin http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb admin/influxdb3
mc admin user add admin influxdb3 <secret>
printf '%s' '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::influxdb3","arn:aws:s3:::influxdb3/*"]}]}' > /tmp/influxdb3.json
mc admin policy create admin influxdb3-rw /tmp/influxdb3.json
mc admin policy attach admin influxdb3-rw --user influxdb3
```

The policy is scoped to that bucket and its objects only. The endpoint in the manifest is
`https://s3.techtales.io` (Traefik on the NAS terminates TLS).

### 2. Admin token

InfluxDB 3 accepts a hand-written token file, so no first-boot bootstrap is needed:

```sh
printf '{"token":"apiv3_%s","name":"_admin"}\n' "$(openssl rand -base64 32 | tr -d '\n')"
```

### 3. OpenBao

Put the values at `infra/kubernetes/main/influxdb/influxdb3`:

| Key              | Value                                       |
| ---------------- | ------------------------------------------- |
| `S3_BUCKET_NAME` | `influxdb3`                                 |
| `S3_ACCESS_KEY`  | the MinIO user from step 1                  |
| `S3_SECRET_KEY`  | its secret                                  |
| `LICENSE_EMAIL`  | mailbox that receives the verification link |
| `ADMIN_TOKEN`    | the `apiv3_…` token from step 2             |

`bao kv put` creates the path; `bao kv patch` fails on a path that does not exist yet.

### 4. Verify the license

Once the pod is `Running`, InfluxData mails a verification link to `LICENSE_EMAIL`. Click it. The
license is then stored in the object store, not in the pod, so a rebuild does not need a second
verification.

### 5. Database and tokens

Exec into the running pod and create the database plus one read token for Grafana and one write
token for Home Assistant:

```sh
ADMIN=$(kubectl -n influxdb exec deploy/influxdb3 -- cat /etc/influxdb3/admin-token.json | jq -r .token)

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create database home_assistant --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --db home_assistant --permission read --name grafana --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --db home_assistant --permission write --name home-assistant --token "$ADMIN"
```

The token comes from the mounted `admin-token.json`, not from an `ADMIN_TOKEN` env key: the
ExternalSecret renders the JSON document as that file.

Add the read token to the same OpenBao entry as `READ_TOKEN`. The ExternalSecret `influxdb3-env`
feeds the app, and Grafana's `influxdb3-grafana-token` reads the same key for its datasource, so a
rotation is one `bao kv patch` plus an ESO refresh on both sides.

## Home Assistant

UI only, not GitOps — HA's configuration lives on its PVC.

Settings > Devices & Services > Add Integration > InfluxDB:

- API version: 2
- URL: `http://influxdb3-app.influxdb.svc.cluster.local:8181`
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
`measurement` variable (`SHOW TABLES`) and the entity from the rows of that table. The datasource
queries with `version: SQL` over FlightSQL, so the plain-HTTP in-cluster URL needs
`insecureGrpc: true`.

## Retention

Unbounded. There are no retention policies; old data is deleted per table with SQL:

```sql
DELETE FROM "<measurement>" WHERE time < '2026-01-01T00:00:00Z';
```

## Verify

```sh
kubectl -n influxdb get pods
kubectl -n influxdb logs deploy/influxdb3
kubectl -n influxdb port-forward svc/influxdb3-app 8181:8181 &
curl -fsS http://127.0.0.1:8181/health
```

After Home Assistant has been writing for a few minutes, the row count comes from a SQL query in
Grafana's Explore (datasource `influxdb`), against one of the unit tables:

```sql
SELECT count(*) FROM "<measurement>";
```

A pod that is `Running` but holds no data usually means the S3 credentials or bucket policy are
wrong — the failure appears in the pod log, not in the readiness check.
