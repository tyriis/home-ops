---
status: accepted
date: 2026-10-24
decision-makers: [tyriis]
---

# One VictoriaMetrics store on utility, native VM custom resources only

Related: ADR 0016 (VictoriaLogs central log platform on utility), ADR 0018 (Loki and promtail
retirement), ADR 0019 (Alertmanager stays the notification layer)

## Context and Problem Statement

Both clusters ran their own `kube-prometheus-stack`: a 3-replica Prometheus per cluster with 14d
retention, each writing to its own PVC, each with its own operator, CRDs, ServiceMonitors and
PrometheusRules. On main that Prometheus PVC sat at roughly **82%** of its volume after 14 days,
which is the steady state, not a spike. Two clusters meant the same stack deployed twice, two
Prometheus UIs nobody opened, two rule dialects to keep in sync, and no way to query one cluster's
metrics from the other without a federation config that was never written.

At the same time utility already hosted the central VictoriaLogs store behind `vmauth` (ADR 0016),
so a metrics front door on the same proxy was a config addition rather than new machinery. The
question this ADR answers: **where does metrics storage live, and in which dialect is it
described?**

## Decision Drivers

- One store, one retention policy, one place to look — instead of two divergent Prometheus TSDBs.
- Main's Prometheus was the single largest stateful consumer on the cluster and was approaching
  full; stopping it frees ~3x PVC plus its memory footprint.
- Per-unit revocation: a token per writer, revocable without touching the other clusters.
- The existing front door (`vmauth`) and its OpenBao/ExternalSecret plumbing are reusable for
  metrics exactly as they are for logs.
- A migration that is reversible per cluster, not a flag day across both.
- No new query language for Grafana: dashboards and alert rules already speak Prometheus.

## Considered Options

- **A. Keep per-cluster Prometheus** (status quo). Rejected: duplicate stack, per-cluster capacity
  pressure, no cross-cluster query, and the 82% PVC grows into a re-shard every few months.
- **B. Prometheus on utility, remote-write from main.** Cheaper on main, but keeps the
  Prometheus-operator model, keeps the 3-replica HA tax on a 1-node cluster (where 3 replicas buy
  nothing) and keeps the deprecated-by-community chart as the storage layer.
- **C. VictoriaMetrics, one `VMSingle` on utility, `VMAgent` on main, native VM CRs only** —
  chosen. Same remote-write API Grafana already understands, aggressive compression, one store,
  and a single binary to operate at the storage end.
- **D. `vmcluster` (vminsert/vmselect/vmstorage) on utility.** Rejected: three stateful components
  plus their PVCs on a **single-node** cluster; it buys scale-out and per-tenant retention the lab
  does not use. `VMSingle` can be graduated to cluster mode later without changing the front door.
- **E. vmagent on main writing to a local `VMSingle` on main, plus federation.** Rejected: two
  stores again — the problem being solved.

## Decision Outcome

Chosen option: **C**.

The outcome below describes the end state. It is implemented in two rollout phases (see
[Rollout phases](#rollout-phases)): the first runs both stacks side by side and removes nothing.

1. **Native VictoriaMetrics custom resources only.** Both clusters run the
   `victoria-metrics-operator` (chart `victoria-metrics-operator` 0.68.1, operator v0.75.0,
   `crds.enabled: true`, `global.versions.metrics: v1.154.1`) with
   `operator.disable_prometheus_converter: true`. Every scrape target and every rule is a
   `VMServiceScrape` / `VMPodScrape` / `VMNodeScrape` / `VMStaticScrape` / `VMProbe` / `VMRule`.
   No `generated-*` objects exist, and a leftover `ServiceMonitor` would be inert rather than
   silently translated — explicit is the point.
2. **Headless `VMAgent` on main.** No local store and no query path: `statefulMode` with a 5Gi
   `ceph-block` persistent queue, `externalLabels.cluster: main`, remote-writing to
   `https://metrics.techtales.io/insert/prometheus/api/v1/write` with the `main-metrics` token.
3. **One `VMSingle` on utility** (30d retention, 50Gi `local-nvme`, 100m/512Mi requests), not
   routable on its own: everything goes through `vmauth` (`victoria-auth`) on
   `metrics.techtales.io`, which already fronts `logs.techtales.io` and `vmalert.techtales.io`.
4. **Per-cluster tokens, per-cluster revocation.** `main-metrics` and `utility-metrics` are
   write-only (`/insert/.*`), `grafana-read` and `vmalert-read` are read-only
   (`/api/v1/.*`, `/prometheus/.*`, `/select/.*`). The values live in the utility path
   `infra/kubernetes/utility/observability/victoria-auth`, which `vmauth` reads; because a
   cluster's `ClusterSecretStore` only grants its own tree, the main-side consumers carry copies
   under `infra/kubernetes/main/observability/`, with rotation touching both. Revoking the main
   cluster's write access is one key rotation; no other unit is affected.
5. **Alerting stays on main.** The 11 `PrometheusRule` manifests become 11 `VMRule`s (twin copies
   during phase 1), evaluated by
   a `VMAlert` CR on main whose datasource is the central store (through vmauth, `vmalert-read`)
   and whose notifier is the in-cluster, headless Alertmanager
   (`alertmanager-operated.observability.svc.cluster.local:9093`). Alertmanager, its CRDs and its
   routes are unchanged — consistent with ADR 0019.
6. **kube-prometheus-stack on main ends up reduced, not removed** (from phase 2 on).
   `prometheus.enabled: false`; the
   chart still supplies Alertmanager, the Alertmanager CRDs, kube-state-metrics and node-exporter,
   which the native VM scrapes target.
7. **Grafana keeps its datasource identity.** The datasource named `prometheus` keeps its name and
   `type: prometheus`; only `url` changes to `https://metrics.techtales.io` with a bearer header
   taken from `VMAUTH_METRICS_AUTHORIZATION`. Dashboards are deliberately not edited, in phase 1 or
   at cutover.
8. **Utility's own kube-prometheus-stack is untouched.** It keeps running Prometheus,
   ServiceMonitors and PrometheusRules until a follow-up migrates that cluster too; the
   `utility-metrics` token exists so that migration is a config-only change.

### Rollout phases

The decision is unchanged by the sequencing; it is reached in two steps so that no metric, alert or
dashboard depends on an unproven path.

1. **Phase 1 — dual-run (this change).** Both stacks run and store in parallel on main.
   Added: the operator on both clusters, the central `VMSingle` behind `vmauth`, the headless
   `VMAgent` on main, the native VM scrape objects, a `VMRule` twin for every app `PrometheusRule`,
   and a `VMAlert` that evaluates those rules from the central store **with no notifier**, so it
   pages nobody. Unchanged: `kube-prometheus-stack` on main keeps `prometheus.enabled` at its
   default (3 replicas, 14d TSDB, `prometheus.techtales.io`), its `ServiceMonitor`s,
   `PodMonitor`s and `PrometheusRule`s, the CNPG/Rook/cert-manager monitor generators, the
   `prometheus` Grafana datasource pointing at `prometheus-operated`, and Alertmanager with its
   routes. Prometheus therefore remains the source of truth and the only paging path, while the VM
   copy is compared against it for a retention window. Reversing phase 1 is deleting the VM app.
2. **Phase 2 — cutover.** `prometheus.enabled: false` and `defaultRules.create: false`, the
   ServiceMonitor `authorization` overrides that exist only with the Prometheus service account,
   the Grafana `prometheus` datasource repointed at `https://metrics.techtales.io` (same name,
   same type), the `VMAlert` notifier enabled at `alertmanager-operated`, the `PrometheusRule`s and
   the generator-produced monitor objects removed, and main's Prometheus PVC deleted by hand after
   a retention cycle.

## Consequences

- Good: one store with one retention policy. Cross-cluster queries work without federation, and
  `cluster="main"` / `cluster="utility"` become ordinary label selectors.
- Good: main drops a 3-replica Prometheus (~82% PVC) and its operator for one small agent; the
  largest stateful workload on the cluster disappears.
- Good: revocation is per cluster. A compromised or retired unit loses write access by rotating
  one token, and read access is a separate token entirely.
- Good: native MetricsQL. Alert rules and dashboard queries are PromQL-compatible in practice,
  with MetricsQL extensions available where the Prometheus dialect forced workarounds.
- Bad: **utility is a single point of failure for metrics across the estate.** If util01 is down,
  main keeps scraping into its queue but nobody can query anything, and main's dashboard and
  `VMAlert` evaluation stop. Availability of the metric platform is now the availability of one
  node — there is no second store.
- Bad: main's ingestion crosses the WAN. Remote write latency, MTU and a Tailscale flap are all
  now in the ingest path; a 5Gi persistent queue buffers the disruption, but a long enough outage
  drops the oldest buffered samples.
- Bad: **main's Prometheus history is lost at cutover.** The 14d TSDB (3 replicas) was not
  imported; the new store starts empty for that cluster. The Prometheus PVC may survive the Helm
  release removal until it is deleted by hand.
- Bad: **two dialects coexist.** Utility still describes its metrics with Prometheus-operator
  objects, so the repo carries both spellings until the follow-up lands. Rule and scrape
  conventions differ per cluster in the meantime.
- Bad: `VMSingle` is single-node with no replication and no object-storage tiering. Retention is
  bounded by one `local-nvme` volume, and losing util01 loses the history.
- Neutral: alert delivery is untouched (ADR 0019), so the blast radius of a metrics outage is
  "no dashboards, no rule evaluation", not "no notifications" — as long as the Alertmanager rump
  on main stays up.

## Follow-ups

- Migrate utility's kube-prometheus-stack to the VM dialect (native scrape objects, `VMRule`,
  `utility-metrics` writer token) and delete its Prometheus. Until then, two stacks remain.
- Delete main's leftover Prometheus PVC once the cutover has been observed for a retention cycle.
- Clean up Gatus / public status checks that assert on main's Prometheus endpoint before phase 2
  removes it.
- Optional: add the VictoriaMetrics Grafana datasource plugin for MetricsQL completion and
  `vmselect` links; keep the plain `prometheus` datasource name either way.

## More Information

- VictoriaMetrics operator: `disable_prometheus_converter`, `VMAgent` `statefulMode`, `VMSingle`
  retention and `search.maxConcurrentRequests` — docs.victoriametrics.com/operator/
- Native CR reference: `VMServiceScrape`, `VMPodScrape`, `VMNodeScrape`, `VMStaticScrape`,
  `VMProbe`, `VMRule`, `VMAlert`
- vmauth per-user `src_paths` allowlists and `deny_paths` catch-alls — docs.victoriametrics.com/victoriametrics/vmauth/
- ADR 0016 (central VictoriaLogs + vmauth front door), ADR 0019 (Alertmanager as notifier)
