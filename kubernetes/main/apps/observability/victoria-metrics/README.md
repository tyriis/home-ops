# VictoriaMetrics central metrics ingestion (main cluster)

Main cluster agent + shared store. The main cluster runs a **headless `VMAgent`** (no local
storage, no query path of its own) and ships every sample over WAN/VPN to the single
`VMSingle` that lives on **utility**, behind the same `vmauth` front door that already serves
VictoriaLogs. Every object in the VM path is a **native VictoriaMetrics CR** — no
`generated-*.yaml` conversion objects (the operator runs with
`operator.disable_prometheus_converter: true`).

This path ships as a **dual-run**: the Prometheus stack on main stays enabled and stays the source
of truth, and this app is a parallel second ingestion path that pages nobody yet. See
[Rollout](#rollout) for what run 1 adds and what run 2 (the cutover) removes.

Operator on both clusters: `kubernetes/{main,utility}/apps/observability/victoria-operator/`,
chart `victoria-metrics-operator` 0.68.1 (operator v0.75.0), `crds.enabled: true`,
`global.versions.metrics: v1.154.1`.

- store: `kubernetes/utility/apps/observability/victoria-metrics/app/vmsingle.yaml`
- front door: `kubernetes/utility/apps/observability/victoria-auth/` (token map below)
- this app: `kubernetes/main/apps/observability/victoria-metrics/app/`

See ADR `docs/decisions/0020-central-metrics-victoriametrics-on-utility.md`.

## Rollout

Two runs. This change is **run 1 only**: nothing on the Prometheus side is removed, and the cutover
is a separate change (run 2).

### Run 1 — dual-run

Both stacks run on main at the same time, both scrape and both store; Prometheus remains the source
of truth.

Added by this change:

- the operator on both clusters, the central `VMSingle` on utility behind `vmauth`, and the
  per-writer / per-reader tokens below;
- the headless `VMAgent` on main, remote-writing every scraped sample to the central store;
- native scrape objects (`VMServiceScrape`, `VMPodScrape`, `VMNodeScrape`, `VMStaticScrape`) that
  mirror the targets Prometheus already scrapes, under their own names;
- a `VMRule` twin beside every app `PrometheusRule`, plus the vendored kube-prometheus-stack set;
- a `VMAlert` that evaluates those `VMRule`s against the central store **with no notifier**: it
  records evaluation health in its own metrics and delivers nothing. Prometheus and the main
  Alertmanager remain the only paging path.

Left exactly as it was on the Prometheus side:

- `prometheus.enabled` keeps its chart default: the 3-replica server, its Service, its
  `prometheus.techtales.io` route and its 14d TSDB keep running and keep answering Grafana;
- every `ServiceMonitor`, `PodMonitor` and `PrometheusRule` stays where it is, and the CNPG, Rook
  and cert-manager monitor generators keep producing theirs;
- the `prometheus` Grafana datasource still points at
  `prometheus-operated.observability.svc.cluster.local:9090`, so dashboards read Prometheus;
- Alertmanager, its routes, receivers, silences and the public `alertmanager.techtales.io`
  endpoint.

Dual-run exists so the new path can be checked against real traffic — `up{cluster="main"}` on the
same targets Prometheus sees, `vmalert_*` evaluation series, and enough days to trust the store —
before Prometheus history becomes unrecoverable. Reversing run 1 is deleting this app; nothing else
moves.

### Run 2 — cutover

- **1.** `prometheus.enabled: false` and `defaultRules.create: false` in
  `kubernetes/main/apps/observability/kube-prometheus-stack/app/helm-release.yaml`, plus the
  ServiceMonitor `authorization` overrides that only exist because the Prometheus service account
  (and its token Secret) goes away with it.
- **2.** Grafana's `prometheus` datasource repointed at `https://metrics.techtales.io` with a
  bearer header — same name, same `type: prometheus`, same `isDefault` — so no dashboard needs an
  edit.
- **3.** `VMAlert` given its `notifier` (`alertmanager-operated`), so rule evaluation starts to
  page through the unchanged Alertmanager.
- **4.** The app `PrometheusRule`s deleted once their `VMRule` twin is the only copy, and the
  CNPG, Rook and cert-manager monitor generators switched off.
- **5.** Main's Prometheus PVC deleted by hand after a retention cycle. The 14d TSDB is not
  imported: dashboards start at the cutover timestamp.

## Architecture

Ingestion path — main has no store, so every write crosses the WAN:

```text
main cluster (ms01, talos01-03)                 utility cluster (util01)

VMServiceScrape / VMPodScrape
VMNodeScrape / VMStaticScrape
        │ discovered by
        ▼
    VMAgent  ───── HTTPS + bearer token ─────▶  envoy   metrics.techtales.io
    headless                                          │
    persistent queue 5Gi ceph-block                   ▼
    externalLabels.cluster=main                  vmauth :8427   (victoria-auth)
                                                      │ user main-metrics → /insert/.*
                                                      ▼
                                                  VMSingle :8428
                                                  30d retention, 50Gi local-nvme
```

Alerting path — rules are evaluated on main from the central store, and in run 1 they deliver
nowhere:

```text
VMRule ──▶ VMAlert
              ├─ datasource ──▶ https://metrics.techtales.io
              │                 (vmauth user vmalert-read → VMSingle on utility)
              └─ notifier   ──▶ none in run 1; added at cutover:
                                  alertmanager-operated.observability.svc.cluster.local:9093
                                  routes / receivers unchanged (Telegram, Grafana OnCall)
```

`VMAlert` queries the **central** store (through vmauth, read-only token) rather than a local
Prometheus, so its evaluation never depends on the Prometheus it runs beside. It has **no
`notifier` in run 1**: every `VMRule` is evaluated on schedule and
`vmalert_alerting_rules_*` / `vmalert_alerts_fired_total` show the result, but no alert leaves the
pod. Paging stays on Prometheus → the main `Alertmanager`, whose routes, receivers and silences are
untouched (ADR 0019). Utility keeps its own `vmalert` + rules for the log pipeline; it is not in
the metrics path.

## Components on main

| Object           | Name                                                          | Notes                                                                     |
| ---------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `VMAgent`        | `vmagent`                                                     | headless, `selectAllByDefault: true`, `externalLabels.cluster: main`      |
| persistent queue | `statefulMode`, 5Gi `ceph-block`                              | replays buffered samples after a WAN blip or pod restart                  |
| `ExternalSecret` | `vmagent-remote-write`                                        | renders the bearer token into Secret `vmagent-remote-write` (key `token`) |
| remote write     | `https://metrics.techtales.io/insert/prometheus/api/v1/write` | token = vmauth user `main-metrics`                                        |
| `VMRule`         | `<app>/app/vm-rule.yaml`                                      | a twin of each app `PrometheusRule`, side by side with it until cutover   |
| `VMAlert`        | `vmalert.yaml`                                                | datasource via vmauth (`vmalert-read`), **no notifier** in run 1          |
| `ExternalSecret` | `vmalert-datasource`                                          | renders the `VMAlert` read token into Secret `vmalert-datasource`         |

kube-prometheus-stack on main is untouched in run 1: the Prometheus server, its CRDs
(`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `Alertmanager`), the Alertmanager and its
config/routes all stay as they are. kube-state-metrics and node-exporter keep coming from the
kube-prometheus-stack subcharts and are scraped **twice** — once by Prometheus through the chart's
`ServiceMonitor`s, once by the native VM objects in `app/scrapes/` — as are Alertmanager itself and
the prometheus-operator, which still emit the metrics the vendored alert rules select. That double
scrape is the point of run 1: it keeps Prometheus complete while the VM copy is compared to it.

## Unit tokens

vmauth carries one user per writer and one per reader. A token is a vmauth **user**, so the
control is the `src_paths` allowlist — the hostname is not a boundary: any token is accepted on
`logs.`, `vmalert.` and `metrics.techtales.io` and can only reach what its own `url_map` allows
(`deny_paths: ["/.*"]` catch-all on everything else, which answers `403`).

| User              | Token env (Secret key)         | Allowed paths                                | Purpose                                                                           |
| ----------------- | ------------------------------ | -------------------------------------------- | --------------------------------------------------------------------------------- |
| `main-metrics`    | `VMAUTH_TOKEN_MAIN_METRICS`    | `/insert/.*`                                 | main vmagent remote write                                                         |
| `utility-metrics` | `VMAUTH_TOKEN_UTILITY_METRICS` | `/insert/.*`                                 | reserved for the utility dialect migration                                        |
| `grafana-read`    | `VMAUTH_TOKEN_GRAFANA_METRICS` | `/api/v1/.*`, `/prometheus/.*`, `/select/.*` | manual read queries in run 1; the Grafana `prometheus` datasource from cutover on |
| `vmalert-read`    | `VMAUTH_TOKEN_VMALERT_METRICS` | `/api/v1/.*`, `/prometheus/.*`, `/select/.*` | main `VMAlert` datasource                                                         |

All four keys exist in **two** OpenBao paths, with the same value in each, because a cluster's
`ClusterSecretStore` policy only grants its own path — main cannot read the utility tree:

- `infra/kubernetes/utility/observability/victoria-auth` — read by `vmauth-tokens` (utility,
  `victoria-auth`), which feeds the `VMAUTH_TOKEN_*` env vars vmauth validates. This is the
  authoritative copy: rotating a key here is what changes what vmauth accepts.
- `infra/kubernetes/main/observability/victoria-metrics` — read by the two main-side
  ExternalSecrets below (`VMAUTH_TOKEN_MAIN_METRICS`, `VMAUTH_TOKEN_VMALERT_METRICS`).
- `infra/kubernetes/main/observability/grafana` — `VMAUTH_TOKEN_GRAFANA_METRICS`, added with the
  Grafana datasource switch in run 2; nothing on main consumes it in run 1.
- `infra/kubernetes/main/observability/opentelemetry` — `VM_METRICS_TOKEN`, the same value as
  `VMAUTH_TOKEN_MAIN_METRICS`, for the OTel collector's OTLP export.

**Rotating a token means patching both copies.** If they diverge, vmauth rejects the cluster-side
consumer with `401` while the utility side keeps working.

The ExternalSecrets involved:

- `vmauth-tokens` (utility, in `victoria-auth`) → Secret `vmauth-tokens`, one key per user, each
  key the literal `VMAUTH_TOKEN_*` env name vmauth reads via `envFrom`.
- `vmagent-remote-write` (main, this app) → Secret `vmagent-remote-write`, the `main-metrics`
  bearer token for remote write.
- `vmalert-datasource` (main, this app) → Secret `vmalert-datasource`, the `vmalert-read` bearer
  token for `VMAlert`'s datasource.

The existing log users on the utility path are untouched.

Retrieve a token (`<KEY>` = column 2):

```sh
kubectl --context readonly@utility -n observability get secret vmauth-tokens \
  -o "jsonpath={.data.<KEY>}" | base64 -d
```

## Write and read endpoints

- Write: `POST https://metrics.techtales.io/insert/prometheus/api/v1/write` (remote write 1.0,
  snappy+protobuf). This is what `VMAgent` uses; `204` = accepted.
- Read / query: `https://metrics.techtales.io/api/v1/*`, `/prometheus/api/v1/*`,
  `/select/*` with a read token — the URL the Grafana `prometheus` datasource moves to at cutover;
  until then only manual queries and `VMAlert` use it.

Smoke test a write token — remote-write itself is binary (snappy+protobuf), so verify it by
observing what `vmagent` reports and what lands in the store, not with a hand-built payload:

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-tokens \
      -o "jsonpath={.data.VMAUTH_TOKEN_GRAFANA_METRICS}" | base64 -d)
for q in 'vmagent_remotewrite_requests_total{cluster="main"}' \
        'vmagent_remotewrite_pending_data_bytes{cluster="main"}' \
        'count(up{cluster="main"})'; do
  curl -s -G -H "Authorization: Bearer $T" --data-urlencode "query=$q" \
    'https://metrics.techtales.io/prometheus/api/v1/query' | head -c 200; echo
done
```

Expected: `requests_total` climbing, `pending_data_bytes` near zero (a growing queue means the
front door or the store is rejecting writes), and a non-empty `up` series count. HTTP statuses
worth knowing: `204` accepted on the write path, `401` for an unknown token, `403` for a write
token on a read path or a read token on `/insert/*`.

Read/query smoke test:

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-tokens \
      -o "jsonpath={.data.VMAUTH_TOKEN_GRAFANA_METRICS}" | base64 -d)
curl -s -H "Authorization: Bearer $T" \
  'https://metrics.techtales.io/prometheus/api/v1/query?query=up%7Bcluster%3D%22main%22%7D' | head -c 300
```

## Native monitor objects and naming rules

| VictoriaMetrics   | mirrors (replaces at cutover)            | `metadata.name` (= job label) rule                                                                             |
| ----------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `VMServiceScrape` | `ServiceMonitor`                         | the `ServiceMonitor` name it mirrors — the default job label dashboards, `VMRule` expressions and panels match |
| `VMPodScrape`     | `PodMonitor`                             | the workload name                                                                                              |
| `VMNodeScrape`    | node-level target (one per node)         | target purpose, e.g. `kubelet`, `kubelet-cadvisor`                                                             |
| `VMStaticScrape`  | `additionalScrapeConfigs` static targets | the component, e.g. `kube-scheduler`                                                                           |
| `VMProbe`         | `Probe` (blackbox exporter)              | the probe name                                                                                                 |

In run 1 every VM object mirrors a live Prometheus-operator object of the same purpose, so both
stacks scrape the same thing; the right-hand column is what disappears at cutover. CoreDNS is one of
them: Prometheus scrapes it through the chart's `kube-prometheus-stack-coredns` `ServiceMonitor`
(`kube-system`, port `http-metrics`/`9153`, job `coredns`), and the VM path mirrors that target in
`app/scrapes/vm-coredns.yaml`, job label included.

File conventions:

- **1. Cluster-wide platform scrapes** live in this app: `app/scrapes/vm-<target>.yaml`
  (`vm-coredns.yaml`, `vm-kube-apiserver.yaml`, `vm-kubelet.yaml`, `vm-node-exporter.yaml`, …). One
  object per file, pulled in by `app/kustomization.yaml`.
- **2. App-owned scrapes** live next to the app that owns the Service, exactly where the
  `ServiceMonitor` lives: `<app>/app/vm-service-scrape.yaml`, or `<app>/app/vm-pod-scrape.yaml`
  when the target is pod-level. One object per file, file name = kind in kebab case.
- **3.** `metadata.name` is the **default job label**, not the file name: normally the name the
  `ServiceMonitor`/`PodMonitor` it mirrors has (`cleanPrometheusOperatorObjectNames: true` made
  those the plain component names). Where the live job differs — operator-generated monitors
  namespace-prefix it (`cnpg-system/postgres17`, `media/immich-db`), chart-rendered ones derive it
  from the chart or the Service (`grafana-service`, `external-secrets-metrics`), and one target
  split across several objects shares a single job (`kubelet-cadvisor` → `kubelet`) — an explicit
  `action: replace` relabel on `job` carries the historical name. The object name and that forced
  value then live apart and must be kept in sync by hand.
- **4.** No `generated-*` objects, and no new `kind: ServiceMonitor` / `PodMonitor` /
  `PrometheusRule` is added for the VM path: the converter is disabled, so such an object would be
  inert rather than translated. The Prometheus-operator objects that already exist stay, for
  Prometheus.

## Scrape objects

Counted from the files under `kubernetes/main` (a multi-document file counts once per object):
1 `VMAgent`, 1 `VMAlert`, 47 `VMServiceScrape`, 12 `VMPodScrape`, 3 `VMNodeScrape`, 5
`VMStaticScrape`, 4 `VMProbe`, 45 `VMRule`. The `VMRule` total is 33 vendored
kube-prometheus-stack rules plus 12 app-owned ones.

## Vendored kube-prometheus-stack rules (`app/rules/kps/`)

kube-prometheus-stack ships its default alert/recording rules as `PrometheusRule`s, and in run 1 the
chart renders them exactly as before — Prometheus evaluates the chart's own copies. The VM side needs
the same rules as native `VMRule`s, and the operator's Prometheus → VM converter is off, so a
`PrometheusRule` cannot be borrowed: the rules are vendored next to this app instead.

- `app/rules/kps/` holds one `VMRule` per source `PrometheusRule` of **chart 92.13.1**, 33 files,
  all pulled in by `app/rules/kps/kustomization.yaml`. Group and alert names, expressions,
  `for:` and labels are unchanged; `spec.groups` is the only structural difference.
- The vendored set was rendered from chart 92.13.1. If the version pinned in `helm-release.yaml`
  moves, these copies are stale — re-render instead of trusting a diff between the two stacks.
- The file name is the source `PrometheusRule` name in kebab case
  (`kube-prometheus-stack-kubernetes-apps.yaml` ← `kube-prometheus-stack-kubernetes-apps`), so a
  file can be traced back to the chart template that produced it.
- Regenerate by re-rendering the chart at the pinned version (`helm template` with this app's
  values), and re-applying the `PrometheusRule` → `VMRule` translation one file per object. Do not
  hand-edit an expression: a diverged copy is invisible until the next regeneration.
- **The Prometheus self-monitoring rules are not vendored on purpose.** The chart's
  `kube-prometheus-stack-prometheus` rule file (23 alerts) selects only the scrape job of the
  Prometheus server itself, and `vmagent` does not scrape that server — it exports its own metrics
  instead. The chart's copy stays with Prometheus; there is no `VMRule` twin and no kustomization
  entry for it.
- Two rule groups needed a scrape before they could work on the VM side: the Alertmanager rules
  (`kube-prometheus-stack-alertmanager.rules.yaml`) and the operator rules
  (`kube-prometheus-stack-prometheus-operator.yaml`). Their scrapes are
  `app/scrapes/vm-alertmanager.yaml` and `app/scrapes/vm-prometheus-operator.yaml`, both of which
  force the `job` label the expressions select:

  | Object            | Service (namespace)                                    | Port                       | Job label (= `metadata.name`)        |
  | ----------------- | ------------------------------------------------------ | -------------------------- | ------------------------------------ |
  | `VMServiceScrape` | `kube-prometheus-stack-alertmanager` (`observability`) | `http-web`, `reloader-web` | `kube-prometheus-stack-alertmanager` |
  | `VMServiceScrape` | `kube-prometheus-stack-operator` (`observability`)     | `https` (TLS)              | `kube-prometheus-stack-operator`     |

  The Alertmanager scrape targets the config Service the chart's `ServiceMonitor` selects
  (`kube-prometheus-stack-alertmanager`), not the headless `alertmanager-operated`, whose labels no
  `ServiceMonitor` matches: scraping both would put every `alertmanager_*` series in the central
  store twice, once per `service` value. The operator is scraped over TLS with `insecureSkipVerify` (its
  serving CA is generated in-cluster and cannot be mounted into `vmagent`) and without a bearer
  token — it exposes `/metrics` unauthenticated on the same TLS port as its web server, exactly
  like the `ServiceMonitor` Prometheus uses.

## CNPG and Rook

Both storage stacks publish `monitoring.coreos.com` objects at runtime for Prometheus. In run 1
those generators stay on, so Prometheus keeps its `PodMonitor`s and `PrometheusRule`s, and the VM
side carries a native twin beside each one:

| Owner                  | Generator to switch off at cutover                          | Native twin                                                      |
| ---------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- |
| CNPG operator (0.29.1) | `monitoring.podMonitorEnabled: false`                       | `cnpg-system/cnpg/operator/` (`vm-pod-scrape`, `vm-rule`)        |
| CNPG `Cluster`         | `spec.monitoring.enablePodMonitor: false`                   | `cnpg-system/cnpg/cluster/vm-pod-scrape.yaml`                    |
| Immich database        | same field on its own `Cluster`                             | `media/immich/database/vm-pod-scrape.yaml`                       |
| rook-ceph-cluster      | `monitoring.enabled: false`, `createPrometheusRules: false` | `rook-ceph/rook-ceph/cluster/` (`vm-service-scrape-*`, `rules/`) |

Both CNPG `Cluster`s (`postgres17` in `cnpg-system`, Immich's database in `media/immich`) still set
`spec.monitoring.enablePodMonitor` in run 1. At cutover the field can go — it is deprecated upstream
since CNPG 1.30 and would then only produce a `PodMonitor` nobody evaluates — and the operator's own
`PodMonitor` is switched off with the chart value `monitoring.podMonitorEnabled: false` instead. The
operator's alert rules already exist as the `VMRule`
`cnpg-system/cnpg/operator/vm-rule.yaml`.

Rook keeps the Ceph `prometheus` mgr module and `ceph-exporter` running — they are what
`vm-service-scrape-mgr.yaml` and `vm-service-scrape-exporter.yaml` scrape — and only the
ServiceMonitor generation is a cutover item. Its alert rules are vendored as
`rook-ceph/rook-ceph/cluster/rules/prometheus-ceph-rules.yaml` for the same reason as the
kube-prometheus-stack set: the VM side needs a `VMRule`, and the converter is off.

## Adding a new scrape target

- **1.** Confirm the target exposes `/metrics` on a **named** Service port (a `targetPort` number
  alone is enough for `VMServiceScrape`, but naming it keeps the object readable).
- **2.** Copy the shape of a neighbour
  (`kubernetes/main/apps/observability/smartctl-exporter/app/vm-service-scrape.yaml` is the
  smallest complete example), including the `# yaml-language-server` schema comment:

  ```yaml
  ---
  # yaml-language-server: $schema=https://k8s-schemas.home-operations.com/operator.victoriametrics.com/vmservicescrape_v1beta1.json
  apiVersion: operator.victoriametrics.com/v1beta1
  kind: VMServiceScrape
  metadata:
    name: my-app # = default job label; reuse the old ServiceMonitor name
  spec:
    namespaceSelector:
      matchNames:
        - <namespace>
    selector:
      matchLabels: # the labels on the Service, not on the Deployment
        app.kubernetes.io/name: my-app
        app.kubernetes.io/instance: my-app
    endpoints:
      - port: http
        path: /metrics
        interval: 1m
  ```

- **3.** Add the file to that directory's `kustomization.yaml`.
- **4.** Nothing else: `selectAllByDefault: true` on the `VMAgent` means every VM scrape object in
  the cluster is picked up on the next config reconcile — no Helm values, no `vmagent` restart.
- **5.** Verify: `kubectl --context admin@main -n <ns> get vmservicescrape my-app`, then query
  `up{job="my-app", cluster="main"}` against `https://metrics.techtales.io` (read token). A new
  target that is up but has no samples usually means a wrong `port` name or `matchLabels`.
- **6.** If the metric set is large, copy the `metricRelabelConfigs` drops from the
  `ServiceMonitor` verbatim — they are cardinality control for the **central** store, and copying
  them keeps both stacks dropping exactly the same series.
- **7.** If the target needs alerts, add a `vm-rule.yaml` (`VMRule`) next to the app's
  `prometheus-rule.yaml` — same directory, same owning unit. In run 1 both copies must exist and
  stay in step: Prometheus evaluates the `PrometheusRule`, the VM side can only evaluate the
  `VMRule` because the converter is off. Run 2 deletes the `PrometheusRule`.

## Dual-run notes

- **Two dialects coexist, and run 1 carries every app rule twice.** Main describes the same targets
  in both spellings — `ServiceMonitor`/`PodMonitor`/`PrometheusRule` for Prometheus,
  `VMServiceScrape`/`VMPodScrape`/`VMRule` for the VM path — while **utility's
  kube-prometheus-stack is untouched** entirely: it runs its own Prometheus, `ServiceMonitor`s and
  `PrometheusRule`s and is not scraped into the central store. Utility's `utility-metrics` token
  exists so that migration is a vmauth-config-only follow-up.
- **Prometheus still owns alert delivery.** `VMAlert` evaluates the `VMRule` copies from the central
  store but has no notifier in run 1, so a `VMRule` that is wrong, noisy or silent changes nothing
  anybody is paged by. Compare `ALERTS{alertname="…", cluster="main"}` in the two stores before
  trusting the VM side.
- **Grafana keeps reading Prometheus.** In run 1 the `prometheus` datasource is untouched, so
  dashboards and their history are untouched. At cutover only `url` changes (plus a bearer header
  from `VMAUTH_METRICS_AUTHORIZATION`); name, `type: prometheus` and `isDefault` stay, so dashboards
  and their datasource references need no edit — that is the point of keeping the name/type.
- **Main's Prometheus history is lost at cutover, not now.** The 14d TSDB (3 replicas, ~82% PVC
  full) was not imported. From cutover on, dashboards show data from that timestamp; there is no
  backfill. The Prometheus PVC may survive the Helm release removal until it is deleted by hand.
- **Alert delivery is unchanged where it matters.** The routes, receivers, silences and the public
  `alertmanager.techtales.io` endpoint stay on the main Alertmanager throughout, and in run 1
  Prometheus keeps feeding it.
- **Cutover checklist** (run 2, in order): `up{cluster="main"}` non-empty via the read token →
  sample count and series count in the expected range → the same query returns the same shape from
  both stores → a dashboard query from Grafana on the VM endpoint → a test `VMRule` alert reaching
  Alertmanager with the notifier attached → only then disable Prometheus and delete its objects.

## Known gaps

- `kube-prometheus-stack-prometheus` is a gap by design: `vmagent` does not scrape the Prometheus
  server's own `/metrics`, so the chart's 23 self-monitoring alerts have no `VMRule` twin and no
  series to evaluate. See the vendored-rules section.
- Main has no local store, so a utility outage means **no metrics on main** (and no queries at
  all). The 5Gi queue protects writes only; dashboards fail during the outage.
- `VMSingle` is single-node, no replication: `local-nvme` on util01 means losing the node loses
  the metric history.
- `metrics.techtales.io` is a WAN dependency for main's ingestion. It is buffered, but a long
  outage grows the queue until `VMAgent` starts dropping the oldest samples.
- kromgo is unaffected in run 1 — its `PROMETHEUS_URL` points at the in-cluster
  `prometheus-operated.observability.svc.cluster.local:9090`, which still has a backend. Cutover
  breaks it: repointing at `https://metrics.techtales.io` is not possible as-is, because kromgo
  sends no `Authorization` header and vmauth answers `401`/`403` without a read token. Same
  decision point as the Ceph dashboard below.
- The Ceph dashboard (`https://rook.techtales.io`) works in run 1 against the in-cluster
  Prometheus. It loses its metrics at cutover: the central endpoint needs a bearer token, which the
  Ceph dashboard cannot send.
- The `apiserver_request(|_sli|_slo)_duration_seconds_bucket` drops inherited from the KPS values
  in `app/scrapes/vm-kube-apiserver.yaml` leave the apiserver burn-rate and SLO rules in
  `rules/kps/` without their input series. That is pre-existing — Prometheus dropped the same
  buckets — so those rules are unusable either way, not a VictoriaMetrics regression.
- Utility's Prometheus is untouched (see the dual-run note above): its history, its
  `ServiceMonitor`s and its `PrometheusRule`s stay where they are until that migration happens.

## Operational notes

- **Token rotation**: patch the `VMAUTH_TOKEN_*` key in **both** copies — the utility path
  (`bao kv patch infra/kubernetes/utility/observability/victoria-auth ...`) and the matching
  main-cluster path from the table above. Stakater reloader
  restarts `vmauth`, `vmagent` and `vmalert` (env is fixed at container start, `%{VAR}` is
  resolved at config parse, so hot-reload alone does not pick up a rotated token).
- **Denied paths return `403`**, not `400`: every metrics user has the `deny_paths: ["/.*"]`
  catch-all in
  `kubernetes/utility/apps/observability/victoria-auth/app/helm-release.yaml`.
- **Capacity**: 30d retention on 50Gi `local-nvme`; watch `vm_free_disk_space_bytes` on the
  `vmsingle` pod. Growing beyond that is a storage-class/PVC change, not an app change.
- **Query storms**: `VMSingle` runs `search.maxConcurrentRequests: 16` and
  `search.maxQueueDuration: 30s`, so a refresh-happy dashboard fails fast instead of starving
  ingestion.
- **vmagent queue**: `statefulMode: true` puts the persistent queue on a 5Gi `ceph-block` PVC.
  Without it the queue is an `emptyDir` and a restart drops whatever was buffered.

## Verification transcript

Filled after run 1 is deployed: the side-by-side comparison (same queries against Prometheus and
`https://metrics.techtales.io`), `vmagent_remotewrite_*` counters and the `VMAlert` evaluation
series.

## Follow-ups

- Run 2 (cutover), the list under [Rollout](#rollout): Prometheus off, Grafana datasource switched,
  `VMAlert` notifier enabled, `PrometheusRule`s and monitor generators removed.
- Migrate utility's kube-prometheus-stack to the same dialect (`utility-metrics` token, VM scrape
  objects, `VMRule`) and delete its Prometheus.
- Delete main's leftover Prometheus PVC once the cutover has been observed for a retention cycle.
- Clean up Gatus / public status checks that assert on main's Prometheus endpoint before run 2
  removes it.
- Decide kromgo's and the Ceph dashboard's read path before run 2 (neither can send a bearer token).
- Optional: VictoriaMetrics Grafana datasource plugin for MetricsQL completion and `vmselect`
  links; the plain `prometheus` datasource stays the safe default until then.
