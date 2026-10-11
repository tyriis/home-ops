# VictoriaLogs central log ingestion (utility cluster)

VictoriaLogs single-node (HelmRelease `victoria-logs`, chart `victoria-logs-single` 0.13.10, VL
v1.53.0) fronted by **vmauth** (HelmRelease `vmauth`, deployed via the bjw-s app-template chart,
OCI-sourced `app-template` 5.2.1) with per-unit bearer tokens. Everything reaches VL through vmauth
on `logs.techtales.io`; VL itself is not routable (NetworkPolicy locks `:9428` to vmauth pods).
The `vmauth` HTTPRoute is rendered by the vmauth HelmRelease itself (app-template `route` section).
See ADR 0016 (`docs/decisions/0016-central-log-platform-victorialogs-on-utility.md`).

## Unit tokens

Each unit authenticates with its own token. All eight tokens live in one Sops-encrypted file
(`secrets.sops.yaml`) as ONE Secret `vmauth-tokens`; each key is the `VMAUTH_TOKEN_*` env name
vmauth reads, so the Deployment maps them with a single `envFrom` block:

| Unit         | Secret key                  | Role                              |
| ------------ | --------------------------- | --------------------------------- |
| main-cluster | `VMAUTH_TOKEN_MAIN_CLUSTER` | write (`/insert/.*` only)         |
| utility      | `VMAUTH_TOKEN_UTILITY`      | write (`/insert/.*` only)         |
| nas          | `VMAUTH_TOKEN_NAS`          | write (`/insert/.*` only)         |
| bifrost      | `VMAUTH_TOKEN_BIFROST`      | write (`/insert/.*` only)         |
| red          | `VMAUTH_TOKEN_RED`          | write (`/insert/.*` only)         |
| purple       | `VMAUTH_TOKEN_PURPLE`       | write (`/insert/.*` only)         |
| synology     | `VMAUTH_TOKEN_SYNOLOGY`     | write (`/insert/.*` only)         |
| grafana      | `VMAUTH_TOKEN_GRAFANA`      | read (`/select/.*`, `/api/v1/.*`) |

Retrieve a unit's token (`<KEY>` = secret key from the table):

```sh
kubectl --context readonly@utility -n observability get secret vmauth-tokens \
  -o "jsonpath={.data.<KEY>}" | base64 -d
```

## Insert endpoint

Ship logs with `POST /insert/jsonline` (VL single-node ignores tenant path segments — use the
plain path):

- LAN: `https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg`
- Tailscale: same hostname — `logs.techtales.io` resolves to the LAN IP over the tunnel.

Per-unit smoke test (example for `main-cluster`, one jsonline line):

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-tokens \
      -o "jsonpath={.data.VMAUTH_TOKEN_MAIN_CLUSTER}" | base64 -d)
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $T" \
  --data-binary '{"msg":"smoke","host":"test","cluster":"utility","unit":"main-cluster","_time":"'"$(date +%s%N)"'"}' \
  'https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg&_time_field=_time'
```

Expected: `204`. Bad/unknown token → `401`. Write token on `/select/*` → `403`. Read token on
`/insert/*` → `403`.

## Grafana datasource

- Type: **Victoria Logs** (`victoriametrics-logs-datasource`)
- URL: `https://logs.techtales.io`
- Custom HTTP header: `Authorization: Bearer <grafana token>` (key `VMAUTH_TOKEN_GRAFANA`
  in `vmauth-tokens`)
- Example LogsQL query: `{cluster="utility"}`

## vmui

`https://logs.techtales.io/select/vmui/` — authenticate with the read token
(key `VMAUTH_TOKEN_GRAFANA` in `vmauth-tokens`).

## Operational notes

- **Token rotation**: per-unit revocation = rotate that unit's `VMAUTH_TOKEN_*` key in the
  single `secrets.sops.yaml` Secret (`vmauth-tokens`), re-encrypt, and push; Stakater reloader
  restarts
  the vmauth pod (env is fixed at container start, `%{VAR}` is resolved at config parse —
  hot-reload alone does NOT pick up rotated tokens).
- **Bad config**: vmauth keeps serving its last good config if a reloaded `vmauth.yaml` has a typo
  (e.g. a mangled `%{VAR}`) — watch pod logs for `invalid config` rather than trusting uptime.
- The read user's `/api/v1/.*` allowance is speculative breadth (the datasource plugin only calls
  `/select/logsql/*`); it is read-only and harmless, trim later if never used.
- Denied paths return `403` because of the per-user `deny_paths` catch-all in
  `vmauth-helm-release.yaml` (the app-template `configMaps` section); without it vmauth returns
  `400` ("missing route").
- On this single-node cluster, host-local processes bypass NetworkPolicy and could reach
  `VL:9428` directly — acceptable at lab trust level.

## Verification transcript

_(filled after deploy)_

## Graduation triggers

From ADR 0016: graduate to Option B (vlcluster) when there is a need for true tenant isolation,
per-unit retention/quota, or ingest beyond single-node comfort. The vmauth config carries over
unchanged (adds tenant path rewrite — see the graduation block in `vmauth-helm-release.yaml`), and
the Grafana source swap is a URL change.
