# InfluxDB 3 Enterprise

Long-term store for Home Assistant sensor history on the main cluster. One pod in the `influxdb`
namespace, ClusterIP-only, with its data in the TrueNAS MinIO bucket `influxdb3` — the pod keeps no
state of its own. Home Assistant pushes state changes to it over the InfluxDB integration and
Grafana reads it back with SQL over FlightSQL. The HA recorder and Prometheus both stay as they are;
this is a third, parallel path beside them.

Decision record:
[ADR 0021](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0021-influxdb3-enterprise-ha-sensor-storage.md).

Source:
[`kubernetes/main/apps/influxdb/influxdb3/app/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/influxdb/influxdb3/app)
— bjw-s app-template `5.3.0`, image `docker.io/library/influxdb:3.12.2-enterprise`.

## Shape

| Item         | Value                                                                |
| ------------ | -------------------------------------------------------------------- |
| Namespace    | `influxdb`                                                           |
| Service      | `influxdb3-app.influxdb.svc.cluster.local:8181`, ClusterIP only      |
| Object store | TrueNAS MinIO `https://s3.techtales.io`, bucket `influxdb3`          |
| Secrets      | OpenBao `infra/kubernetes/main/influxdb/influxdb3` → `influxdb3-env` |
| License      | Enterprise "home" tier, verified once by email, stored in the bucket |
| Retention    | Unbounded, no retention policy; delete with SQL                      |

The license check is a first-boot step: InfluxData mails the verification link to `LICENSE_EMAIL`
once the pod is running, and a rebuild afterwards does not need a second verification.

## Provisioning

Two hand-run prerequisites, neither of them GitOps: the MinIO bucket and user (policy scoped to
`influxdb3` and its objects), and the `apiv3_…` admin token generated offline with
`openssl rand -base64 32`. Both land in the OpenBao entry above. Once the pod is up, the database and
its two database-scoped tokens are created inside the pod:

```sh
ADMIN=$(kubectl -n influxdb exec deploy/influxdb3 -- cat /etc/influxdb3/admin-token.json | jq -r .token)

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create database home_assistant --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --db home_assistant --permission read --name grafana --token "$ADMIN"

kubectl -n influxdb exec deploy/influxdb3 -- \
  influxdb3 create token --db home_assistant --permission write --name home-assistant --token "$ADMIN"
```

The read token is stored as `READ_TOKEN` in the same OpenBao entry. Two consumers read that key:
the app's own `ExternalSecret`, and `influxdb3-grafana-token` in the Grafana app, which feeds the
`influxdb` datasource. Rotating it is one `bao kv patch` plus an ESO refresh on both sides.

The token is read from the mounted `admin-token.json`; the Secret carries no `ADMIN_TOKEN` key.

## Home Assistant

UI only — HA's configuration lives on its PVC, so this is not in the repository. Settings > Devices &
Services > Add Integration > InfluxDB: API version 2, URL
`http://influxdb3-app.influxdb.svc.cluster.local:8181`, bucket/database `home_assistant`,
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
variable (`SHOW TABLES`) and the entity from that table's rows.

## Verify

```sh
kubectl -n influxdb get pods
kubectl -n influxdb logs deploy/influxdb3
kubectl -n influxdb port-forward svc/influxdb3-app 8181:8181 &
curl -fsS http://127.0.0.1:8181/health
```

Then, after Home Assistant has been writing for a few minutes, from Grafana's Explore on the
`influxdb` datasource, against one of the unit tables:

```sql
SELECT count(*) FROM "<measurement>";
```

A `Running` pod that holds no data means the S3 credentials or bucket policy are wrong; the pod log
carries the failure, the readiness check does not.

## Retention

No retention policies exist. Old data is deleted per table:

```sql
DELETE FROM "<measurement>" WHERE time < '2026-01-01T00:00:00Z';
```
