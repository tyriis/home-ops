# VictoriaMetrics central metrics ingestion (main cluster)

Main cluster agent + shared store. The main cluster runs a **headless `VMAgent`** (no local
storage, no query path of its own) and ships every sample over WAN/VPN to the single
`VMSingle` that lives on **utility**, behind the same `vmauth` front door that already serves
VictoriaLogs. Everything is a **native VictoriaMetrics CR** — no Prometheus-operator objects,
no `generated-*.yaml` conversion objects (the operator runs with
`operator.disable_prometheus_converter: true`).

Operator on both clusters: `kubernetes/{main,utility}/apps/observability/victoria-operator/`,
chart `victoria-metrics-operator` 0.68.1 (operator v0.75.0), `crds.enabled: true`,
`global.versions.metrics: v1.154.1`.

- store: `kubernetes/utility/apps/observability/victoria-metrics/app/vmsingle.yaml`
- front door: `kubernetes/utility/apps/observability/victoria-auth/` (token map below)
- this app: `kubernetes/main/apps/observability/victoria-metrics/app/`

See ADR `docs/decisions/0020-central-metrics-victoriametrics-on-utility.md`.

## Architecture

Ingestion path — main has no store, so every write crosses the WAN:

```text
main cluster (ms01, talos01-03)                 utility cluster (util01)

VMServiceScrape / VMPodScrape
VMNodeScrape / VMStaticScrape
        │ discovered by
        ▼
    VMAgent  ───── HTTPS + bearer token ─────▶  envoy   metrics.techtales.io
    headless                                         │
    persistent queue 5Gi ceph-block                  ▼
    externalLabels.cluster=main                  vmauth :8427   (victoria-auth)
                                                     │ user main-metrics → /insert/.*
                                                     ▼
                                                  VMSingle :8428
                                                  30d retention, 50Gi local-nvme
```

Alerting path — rules are evaluated on main, delivery stays with the in-cluster Alertmanager:

```text
VMRule ──▶ VMAlert
              ├─ datasource ──▶ https://metrics.techtales.io
              │                 (vmauth user vmalert-read → VMSingle on utility)
              └─ notifier   ──▶ alertmanager-operated.observability.svc.cluster.local:9093
                                  └─ routes / receivers unchanged (Telegram, Grafana OnCall)
```

`VMAlert` queries the **central** store (through vmauth, read-only token) rather than a local
Prometheus. It keeps the main `Alertmanager` as its notifier, so routes, receivers and silences
are unchanged (ADR 0019). Utility keeps its own `vmalert` + rules for the log pipeline; it is not
in the metrics path.

## Components on main

| Object           | Name                                                          | Notes                                                                        |
| ---------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `VMAgent`        | `vmagent`                                                     | headless, `selectAllByDefault: true`, `externalLabels.cluster: main`         |
| persistent queue | `statefulMode`, 5Gi `ceph-block`                              | replays buffered samples after a WAN blip or pod restart                     |
| `ExternalSecret` | `vmagent-remote-write`                                        | renders the bearer token into Secret `vmagent-remote-write` (key `token`)    |
| remote write     | `https://metrics.techtales.io/insert/prometheus/api/v1/write` | token = vmauth user `main-metrics`                                           |
| `VMRule`         | `<app>/app/vm-rule.yaml`                                      | the 11 former `PrometheusRule` manifests, renamed in place next to their app |
| `VMAlert`        | `vmalert.yaml`                                                | datasource via vmauth (`vmalert-read`), notifier = main Alertmanager         |
| `ExternalSecret` | `vmalert-datasource`                                          | renders the `VMAlert` read token into Secret `vmalert-datasource`            |

kube-prometheus-stack on main is reduced to a rump: `prometheus.enabled: false`, while
Alertmanager, its CRDs (`Alertmanager`, `AlertmanagerConfig`) and the alertmanager config/routes
stay exactly as they were. kube-state-metrics and node-exporter still come from the
kube-prometheus-stack subcharts and are scraped by the native VM objects in `app/scrapes/` — as
are Alertmanager itself and the prometheus-operator, which still run and still emit the metrics
their vendored alert rules select.

## Unit tokens

vmauth carries one user per writer and one per reader. A token is a vmauth **user**, so the
control is the `src_paths` allowlist — the hostname is not a boundary: any token is accepted on
`logs.`, `vmalert.` and `metrics.techtales.io` and can only reach what its own `url_map` allows
(`deny_paths: ["/.*"]` catch-all on everything else, which answers `403`).

| User              | Token env (Secret key)         | Allowed paths                                | Purpose                                                 |
| ----------------- | ------------------------------ | -------------------------------------------- | ------------------------------------------------------- |
| `main-metrics`    | `VMAUTH_TOKEN_MAIN_METRICS`    | `/insert/.*`                                 | main vmagent remote write                               |
| `utility-metrics` | `VMAUTH_TOKEN_UTILITY_METRICS` | `/insert/.*`                                 | reserved for the utility dialect migration              |
| `grafana-read`    | `VMAUTH_TOKEN_GRAFANA_METRICS` | `/api/v1/.*`, `/prometheus/.*`, `/select/.*` | Grafana `prometheus` datasource, dashboards, `vmselect` |
| `vmalert-read`    | `VMAUTH_TOKEN_VMALERT_METRICS` | `/api/v1/.*`, `/prometheus/.*`, `/select/.*` | main `VMAlert` datasource                               |

All four keys exist in **two** OpenBao paths, with the same value in each, because a cluster's
`ClusterSecretStore` policy only grants its own path — main cannot read the utility tree:

- `infra/kubernetes/utility/observability/victoria-auth` — read by `vmauth-tokens` (utility,
  `victoria-auth`), which feeds the `VMAUTH_TOKEN_*` env vars vmauth validates. This is the
  authoritative copy: rotating a key here is what changes what vmauth accepts.
- `infra/kubernetes/main/observability/victoria-metrics` — read by the two main-side
  ExternalSecrets below (`VMAUTH_TOKEN_MAIN_METRICS`, `VMAUTH_TOKEN_VMALERT_METRICS`).
- `infra/kubernetes/main/observability/grafana` — `VMAUTH_TOKEN_GRAFANA_METRICS` for the Grafana
  datasource, next to the existing Grafana OAuth keys.
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
  `/select/*` with a read token — that is the same URL the Grafana datasource uses.

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

| VictoriaMetrics   | replaces                                 | `metadata.name` (= job label) rule                                                               |
| ----------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `VMServiceScrape` | `ServiceMonitor`                         | the old `ServiceMonitor` name — dashboards, `VMRule` expressions and panels keep matching `job=` |
| `VMPodScrape`     | `PodMonitor`                             | the workload name                                                                                |
| `VMNodeScrape`    | node-level target (one per node)         | target purpose, e.g. `kubelet`, `kubelet-cadvisor`                                               |
| `VMStaticScrape`  | `additionalScrapeConfigs` static targets | the component, e.g. `kube-scheduler`                                                             |
| `VMProbe`         | `Probe` (blackbox exporter)              | the probe name                                                                                   |

File conventions:

1. **Cluster-wide platform scrapes** live in this app: `app/scrapes/vm-<target>.yaml`
   (`vm-kube-apiserver.yaml`, `vm-kubelet.yaml`, `vm-node-exporter.yaml`, …). One object per file,
   pulled in by `app/kustomization.yaml`.
2. **App-owned scrapes** live next to the app that owns the Service, exactly where the
   `ServiceMonitor` lived: `<app>/app/vm-service-scrape.yaml`, or `<app>/app/vm-pod-scrape.yaml`
   when the target is pod-level. One object per file, file name = kind in kebab case.
3. `metadata.name` is the **job label**, not the file name. It must be the name the removed
   `ServiceMonitor`/`PodMonitor` had (`cleanPrometheusOperatorObjectNames: true` made those the
   plain component names).
4. No `generated-*` objects and no `kind: ServiceMonitor` anywhere: the converter is disabled, so
   a Prometheus-operator object would be inert rather than translated.

## Vendored kube-prometheus-stack rules (`app/rules/kps/`)

kube-prometheus-stack still ships its default alert/recording rules, but the chart no longer
renders them: `defaultRules.create: false` in
`kubernetes/main/apps/observability/kube-prometheus-stack/app/helm-release.yaml`. With Prometheus
gone and the operator's Prometheus → VM converter off, a rendered `PrometheusRule` would be inert,
so the rules are vendored next to this app instead.

- `app/rules/kps/` holds one `VMRule` per source `PrometheusRule` of **chart 92.11.0**, 33 files,
  all pulled in by `app/rules/kps/kustomization.yaml`. Group and alert names, expressions,
  `for:` and labels are unchanged; `spec.groups` is the only structural difference.
- The file name is the source `PrometheusRule` name in kebab case
  (`kube-prometheus-stack-kubernetes-apps.yaml` ← `kube-prometheus-stack-kubernetes-apps`), so a
  file can be traced back to the chart template that produced it.
- Regenerate by re-rendering the chart at the pinned version (`helm template` with this app's
  values, then `defaultRules.create: true`), and re-applying the `PrometheusRule` → `VMRule`
  translation one file per object. Do not hand-edit an expression: a diverged copy is invisible
  until the next regeneration.
- **The Prometheus self-monitoring rules are excluded on purpose.** The chart's
  `kube-prometheus-stack-prometheus` rule file (23 alerts) selects only the scrape job of the
  Prometheus server itself, which does not exist here, so it is not vendored and its kustomization
  entry and file are gone.
- Two rule groups that _do_ still have a producer needed scraping before they could work: the
  Alertmanager rules (`kube-prometheus-stack-alertmanager.rules.yaml`) and the operator rules
  (`kube-prometheus-stack-prometheus-operator.yaml`). Their scrapes are
  `app/scrapes/vm-alertmanager.yaml` and `app/scrapes/vm-prometheus-operator.yaml`, both of which
  force the `job` label the expressions select:

  | Object            | Service (namespace)                                    | Port                       | Job label (= `metadata.name`)        |
  | ----------------- | ------------------------------------------------------ | -------------------------- | ------------------------------------ |
  | `VMServiceScrape` | `kube-prometheus-stack-alertmanager` (`observability`) | `http-web`, `reloader-web` | `kube-prometheus-stack-alertmanager` |
  | `VMServiceScrape` | `kube-prometheus-stack-operator` (`observability`)     | `https` (TLS)              | `kube-prometheus-stack-operator`     |

  The Alertmanager scrape targets the config Service, not the headless
  `alertmanager-operated` one: both select the same pods, so scraping both would duplicate every
  `alertmanager_*` series under two job names. The operator is scraped over TLS with
  `insecureSkipVerify` (its serving CA is generated in-cluster and cannot be mounted into
  `vmagent`) and without a bearer token — it exposes `/metrics` unauthenticated on the same TLS
  port as its web server, exactly like the removed `ServiceMonitor`.

## CNPG and Rook

Both storage stacks used to publish `monitoring.coreos.com` objects at runtime. Those generators
are off and the objects are native VM ones:

| Owner                  | Generator turned off                                        | Native objects                                                   |
| ---------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- |
| CNPG operator (0.29.1) | `monitoring.podMonitorEnabled: false`                       | `cnpg-system/cnpg/operator/` (`vm-pod-scrape`, `vm-rule`)        |
| CNPG `Cluster`         | `spec.monitoring.enablePodMonitor: false`                   | `cnpg-system/cnpg/cluster/vm-pod-scrape.yaml`                    |
| Immich database        | same field on its own `Cluster`                             | `media/immich/database/vm-pod-scrape.yaml`                       |
| rook-ceph-cluster      | `monitoring.enabled: false`, `createPrometheusRules: false` | `rook-ceph/rook-ceph/cluster/` (`vm-service-scrape-*`, `rules/`) |

Both CNPG `Cluster`s (`postgres17` in `cnpg-system`, Immich's database in `media/immich`) set
`monitoring.enablePodMonitor: false`; the field is deprecated upstream since CNPG 1.30 and would
only produce a `PodMonitor` nobody evaluates. The operator's own `PodMonitor` is off via the chart
value instead, and its alert rules are the `VMRule` `cnpg-system/cnpg/operator/vm-rule.yaml`.

Rook keeps the Ceph `prometheus` mgr module and `ceph-exporter` running — only the ServiceMonitor
generation is off — so `vm-service-scrape-mgr.yaml` and `vm-service-scrape-exporter.yaml` find
real targets. Its alert rules are vendored as
`rook-ceph/rook-ceph/cluster/rules/prometheus-ceph-rules.yaml` for the same reason as the
kube-prometheus-stack set: the chart would otherwise render a `PrometheusRule` nobody evaluates.

## Adding a new scrape target

1. Confirm the target exposes `/metrics` on a **named** Service port (a `targetPort` number alone
   is enough for `VMServiceScrape`, but naming it keeps the object readable).
2. Copy the shape of a neighbour (`kubernetes/main/apps/observability/smartctl-exporter/app/vm-service-scrape.yaml`
   is the smallest complete example), including the `# yaml-language-server` schema comment:

   ```yaml
   ---
   # yaml-language-server: $schema=https://k8s-schemas.home-operations.com/operator.victoriametrics.com/vmservicescrape_v1beta1.json
   apiVersion: operator.victoriametrics.com/v1beta1
   kind: VMServiceScrape
   metadata:
     name: my-app # = job label; reuse the old ServiceMonitor name
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

3. Add the file to that directory's `kustomization.yaml`.
4. Nothing else: `selectAllByDefault: true` on the `VMAgent` means every VM scrape object in the
   cluster is picked up on the next config reconcile — no Helm values, no `vmagent` restart.
5. Verify: `kubectl --context admin@main -n <ns> get vmservicescrape my-app`, then query
   `up{job="my-app", cluster="main"}` against `https://metrics.techtales.io` (read token). A new
   target that is up but has no samples usually means a wrong `port` name or `matchLabels`.
6. If the metric set is large, port the `metricRelabelConfigs` drops from the old monitor
   verbatim — they are cardinality control for the **central** store now, not for a per-cluster
   Prometheus.
7. If the target needs alerts, rename/convert its `prometheus-rule.yaml` to `vm-rule.yaml`
   (`VMRule`) next to the app — same directory, same owning unit. Never leave a `PrometheusRule`
   behind: the converter is disabled, so it would never be evaluated.

## Dual-run and cutover notes

- **Two dialects coexist.** Main is VM-native (`VMServiceScrape`/`VMPodScrape`/`VMRule`, query
  language MetricsQL) while **utility's kube-prometheus-stack is untouched** — it still runs its
  own Prometheus, `ServiceMonitor`s and `PrometheusRule`s and is not scraped into the central
  store. Utility's `utility-metrics` token exists so that migration is a vmauth-config-only
  follow-up.
- **Main's Prometheus history is lost at cutover.** The 14d TSDB (3 replicas, ~82% PVC full) was
  not imported. Dashboards show the new data from the cutover timestamp onward; there is no
  backfill. The Prometheus PVC may survive the Helm release removal until it is deleted by hand.
- **Grafana keeps its datasource identity.** The `prometheus` datasource keeps its name and type;
  only `url` changed to `https://metrics.techtales.io` with a bearer header from
  `VMAUTH_METRICS_AUTHORIZATION`. Dashboards were deliberately not edited — that is the point of
  keeping the name/type.
- **Alerting is unchanged where it matters.** Rules are now `VMRule` objects evaluated by
  `VMAlert`, but delivery is still the in-cluster Alertmanager (`alertmanager-operated`), so
  Telegram routes, silences and the public `alertmanager.techtales.io` endpoint did not move.
- **Cutover checklist** (in order): `up{cluster="main"}` non-empty via the read token → sample
  count and series count in the expected range → a dashboard query from Grafana → a test
  `VMRule` alert reaching Alertmanager → only then remove the last Prometheus pieces.

## Known gaps

- CoreDNS is not scraped: its Service never exposed `9153`, so there was nothing to convert.
- Main has no local store, so a utility outage means **no metrics on main** (and no queries at
  all). The 5Gi queue protects writes only; dashboards fail during the outage.
- `VMSingle` is single-node, no replication: `local-nvme` on util01 means losing the node loses
  the metric history.
- `metrics.techtales.io` is a WAN dependency for main's ingestion. It is buffered, but a long
  outage grows the queue until `VMAgent` starts dropping the oldest samples.
- kromgo still points its `PROMETHEUS_URL` at the in-cluster
  `prometheus-operated.observability.svc.cluster.local:9090`, which no longer has a backend.
  Repointing it at `https://metrics.techtales.io` is not possible as-is: kromgo sends no
  `Authorization` header, and vmauth answers `401`/`403` without a read token.
- The Ceph dashboard (`https://rook.techtales.io`) has no Prometheus integration any more. It
  could only reach the removed in-cluster Prometheus; the central endpoint needs a bearer token,
  which the Ceph dashboard cannot send.
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

Filled after deploy.

## Follow-ups

- Migrate utility's kube-prometheus-stack to the same dialect (`utility-metrics` token, VM scrape
  objects, `VMRule`) and delete its Prometheus.
- Delete main's leftover Prometheus PVC once the cutover is confirmed.
- Clean up Gatus / public status checks that still assert on the removed Prometheus endpoint.
- Optional: VictoriaMetrics Grafana datasource plugin for MetricsQL completion and `vmselect`
  links; the plain `prometheus` datasource stays the safe default until then.
