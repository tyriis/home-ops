# VictoriaLogs central log ingestion (utility cluster)

VictoriaLogs single-node (HelmRelease `victoria-logs`, chart `victoria-logs-single` 0.13.10, VL
v1.53.0) fronted by **vmauth** with per-unit bearer tokens. Everything reaches VL through vmauth
on `logs.techtales.io`; VL itself is not routable (NetworkPolicy locks `:9428` to vmauth pods).
See ADR 0016 (`docs/decisions/0016-central-log-platform-victorialogs-on-utility.md`).

## Unit tokens

Each unit authenticates with its own token, stored as a separate Sops-encrypted Secret (key
`token`):

| Unit        | Secret name                | Role                              |
| ----------- | -------------------------- | --------------------------------- |
| ms01        | `vmauth-token-ms01`        | write (`/insert/.*` only)         |
| utility     | `vmauth-token-utility`     | write (`/insert/.*` only)         |
| nas         | `vmauth-token-nas`         | write (`/insert/.*` only)         |
| bifrost     | `vmauth-token-bifrost`     | write (`/insert/.*` only)         |
| workstation | `vmauth-token-workstation` | write (`/insert/.*` only)         |
| remote      | `vmauth-token-remote`      | write (`/insert/.*` only)         |
| grafana     | `vmauth-token-grafana`     | read (`/select/.*`, `/api/v1/.*`) |

Retrieve a unit's token:

```sh
kubectl --context readonly@utility -n observability get secret vmauth-token-UNIT \
  -o 'jsonpath={.data.token}' | base64 -d
```

## Insert endpoint

Ship logs with `POST /insert/jsonline` (VL single-node ignores tenant path segments — use the
plain path):

- LAN: `https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg`
- Tailscale: same hostname — `logs.techtales.io` resolves to the LAN IP over the tunnel.

Per-unit smoke test (example for `ms01`, one jsonline line):

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-token-ms01 \
      -o 'jsonpath={.data.token}' | base64 -d)
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $T" \
  --data-binary '{"msg":"smoke","host":"test","cluster":"utility","unit":"ms01","_time":"'"$(date +%s%N)"'"}' \
  'https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg&_time_field=_time'
```

Expected: `204`. Bad/unknown token → `401`. Write token on `/select/*` → `403`. Read token on
`/insert/*` → `403`.

## Grafana datasource

- Type: **Victoria Logs** (`victoriametrics-logs-datasource`)
- URL: `https://logs.techtales.io`
- Custom HTTP header: `Authorization: Bearer <grafana token>` (from `vmauth-token-grafana`)
- Example LogsQL query: `{cluster="utility"}`

## vmui

`https://logs.techtales.io/select/vmui/` — authenticate with the read token
(`vmauth-token-grafana`).

## Operational notes

- **Token rotation**: edit + re-encrypt the unit's sops Secret and push; Stakater reloader restarts
  the vmauth pod (env is fixed at container start, `%{VAR}` is resolved at config parse —
  hot-reload alone does NOT pick up rotated tokens).
- **Bad config**: vmauth keeps serving its last good config if a reloaded `vmauth.yaml` has a typo
  (e.g. a mangled `%{VAR}`) — watch pod logs for `invalid config` rather than trusting uptime.
- The read user's `/api/v1/.*` allowance is speculative breadth (the datasource plugin only calls
  `/select/logsql/*`); it is read-only and harmless, trim later if never used.
- Denied paths return `403` because of the per-user `deny_paths` catch-all in
  `vmauth-configmap.yaml`; without it vmauth returns `400` ("missing route").
- On this single-node cluster, host-local processes bypass NetworkPolicy and could reach
  `VL:9428` directly — acceptable at lab trust level.

## Verification transcript

_(filled after deploy)_

## Graduation triggers

From ADR 0016: graduate to Option B (vlcluster) when there is a need for true tenant isolation,
per-unit retention/quota, or ingest beyond single-node comfort. The vmauth config carries over
unchanged (adds tenant path rewrite — see the graduation block in `vmauth-configmap.yaml`), and
the Grafana source swap is a URL change.
