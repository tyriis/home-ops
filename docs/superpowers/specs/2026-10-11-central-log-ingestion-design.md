# Central Log Ingestion on utility — Phase 1 Design Spec

Date: 2026-10-11
Status: approved for implementation
ADR: `docs/decisions/0016-central-log-platform-victorialogs-on-utility.md` (Option C)

## Goal

Deploy the utility-side half of the central log platform (ADR 0016, Option C):
VictoriaLogs single-node behind vmauth with per-unit write tokens and one
read-only Grafana token. Phase 1 is utility-side only — no shipper rollouts.

## Decided parameters (not re-litigated)

- **Backend**: `victoria-logs-single` HelmRelease (VictoriaMetrics community
  chart), 1 replica, `-retentionPeriod=30d`, requests ~100m CPU / 512Mi RAM.
  No Loki, no S3/MinIO, no cluster mode. Metrics out of scope, but the vmauth
  config stays extensible so a metrics backend can be added as extra users.
- **Front door**: `vmauth` Deployment + Service in front of VL. VL gets no
  Ingress route. A NetworkPolicy allows only vmauth to reach VL on 9428.
- **Per-unit credentials (R2)**: one vmauth user per unit — `ms01`, `utility`,
  `nas`, `bifrost`, `workstation`, `remote` — bearer token, write-only,
  `src_paths` locked to `/insert/.*` only. One read-only user
  `grafana-readonly` locked to `/select/.*` + `/api/v1/.*` for the
  `victoriametrics-logs-datasource` Grafana plugin.
- **Tokens (answers ADR open question #4)**: distinct random tokens, each
  stored as a Sops secret in the owning unit's config area (not one
  mega-secret); vmauth consumes them via a projected Secret mount.
- **Source labeling (R3\*)**: shippers self-set `host=`/`cluster=` labels;
  vmauth proves the key, not the payload. Spoof trade-off accepted —
  documented, not engineered around.
- **Graduation path**: the vmauth ConfigMap carries a commented block showing
  the later metrics-backend users and vlcluster tenant-rewrite changes.
  Not implemented now.

## Resolved open questions

1. **PVC placement (ADR q1)**: reuse the existing `local-nvme` StorageClass
   (democratic-csi local-hostpath on util01's local disk, already hosting
   kube-prometheus-stack and forgejo). Logs are disposable; zero Ceph/NFS
   write amplification. A dedicated disk/SC is unnecessary for 20Gi.
2. **Endpoint exposure (ADR q2)**: LAN + Tailscale. HTTPRoute
   `logs.techtales.io` on the existing Envoy Gateway (`envoy` in
   `networking`, `*.techtales.io` wildcard cert) for LAN clients, and
   reachable over Tailscale for the remote site (DNS resolves to the LAN IP
   the tunnel routes to).
3. **Namespace**: existing `observability` namespace in
   `kubernetes/utility/apps/observability/` (repo convention: apps grouped per
   namespace; logs sit beside metrics).
4. **Shipper choice (ADR q3)**: unchanged from ADR — decided per unit during
   the phase-2 rollout. Phase 1 only needs the insert endpoint to exist.
5. **Grafana read path (ADR q5)**: read-only vmauth user ships now (part of
   the initial user map), so Grafana never points at VL directly.

## Deliverables (phase 1)

App tree under `kubernetes/utility/apps/observability/victoria-logs/`:

1. **Flux wiring**: app-local `HelmRepository victoria-metrics-charts` in the app
   dir (harbor convention); app registered in the
   observability namespace kustomization.
2. **HelmRelease `victoria-logs`**: victoria-logs-single chart, persistence
   enabled on `local-nvme`, 20Gi, retention 30d, resources per above.
3. **vmauth**: Deployment + Service + ConfigMap (`vmauth.yaml`), consuming
   7 Sops secrets (6 unit write tokens + 1 Grafana read token) as env vars
   templated into the config; hot-reload via vmauth's built-in config check
   (config-check + SIGHUP or config-reloader if needed).
4. **NetworkPolicy**: VL pod ingress only from the vmauth pod selector on
   9428. vmui served through the same read user (no extra allowance).
5. **HTTPRoute**: `logs.techtales.io` → vmauth Service, following the
   existing envoy-gateway pattern (`external-dns/unifi` annotation).
6. **vmauth user map**: 6 write users (`/insert/.*` only) + 1 read user
   (`/select/.*`, `/api/v1/.*`), plus the commented graduation block
   (metrics users, vlcluster tenant rewrite).
7. **README** in the app dir: unit → token-secret-name table, insert URL per
   network path (LAN / Tailscale), curl examples per unit, Grafana datasource
   config (URL + read token), ADR graduation triggers.
8. **ADR status flip** to `accepted` once deployed, with a note recording
   resolved questions #1 and #2.

## Verification (evidence pasted into the PR)

- `kubectl -n observability get pods,pvc,helmrelease` — everything green.
- Insert smoke via exposed URL with the utility token → HTTP 204.
- Wrong-token insert → 401; write token against `/select/` → 401/403.
- Query back with the read user (`{host="test"}`) and confirm line + labels.
- vmui reachable through the read user, or explicitly disabled.

## Out of scope (phase 2)

Shipper DaemonSets on ms01/utility, NAS fluent-bit output, bifrost and
workstation agents, remote-site agent — rolled out one unit at a time, each
with its own token. Grafana dashboards (datasource wiring only). VL PVC
disk-usage alert (deferred until alerting infra is convenient).
