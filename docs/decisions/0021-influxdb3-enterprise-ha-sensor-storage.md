---
status: proposed
date: 2026-09-17
decision-makers: [tyriis]
---

# InfluxDB 3 Enterprise as long-term store for Home Assistant sensor data

## Context and Problem Statement

Home Assistant's default recorder stores state history in a relational DB with limited
practical retention; long-term sensor history (temperature, humidity, energy) gets purged.
Issue [tyriis/home-ops#39](https://github.com/tyriis/home-ops/issues/39) proposed evaluating
influxdb vs graphite vs prometheus/mimir for long-term data-point storage.

Constraints discovered during evaluation:

- The HA recorder must NOT be replaced — the InfluxDB integration runs parallel to it.
- kube-prometheus-stack must NOT be replaced — cluster metrics stay on Prometheus.
- Ingestion must be native/bridgeless where possible (HA has a push integration for InfluxDB 1.x/2.x/3.x; Graphite and Mimir have none).
- Retention must be long-term/unbounded.

## Decision Drivers

- Native Home Assistant integration (zero middleware)
- Long-term (multi-year) retention without manual babysitting
- Fits existing infra: app-template deploy pattern, MinIO object storage, Grafana as single pane of glass
- GitOps-homelab deployability (Flux + app-template, no bespoke operator)
- Low operational overhead for a single-node Talos cluster

## Considered Options

- VictoriaMetrics / Thanos / Mimir as unified TSDB (Prometheus remote_write)
- Graphite
- InfluxDB 1.x (official influxdata Helm chart)
- InfluxDB 2.x
- InfluxDB 3 Core
- InfluxDB 3 Enterprise (free "home" license)

## Decision Outcome

Chosen option: "InfluxDB 3 Enterprise (free home license)", because it is the only
InfluxDB 3 variant without a query-range cap, its only extra requirement (S3-compatible
object storage) is already satisfied by MinIO, and Home Assistant can push sensor data
to it natively.

Placement: namespace `observability`, ClusterIP-only (cluster-internal access),
deployed via bjw-s app-template as a plain container — no official Helm chart exists
for 2.x/3.x. Reference implementation:
[gavinmcfall/home-ops](https://github.com/gavinmcfall/home-ops/blob/main/kubernetes/apps/database/influxdb3/app/helmrelease.yaml)
(37 stars).

### Consequences

- Good, parallel data paths: Prometheus keeps cluster metrics; InfluxDB owns HA sensor data; Grafana queries both.
- Good, data durability: Parquet/Arrow objects live in MinIO; InfluxDB 3 compute is effectively stateless.
- Good, retention is a runtime decision, not architecture: no automatic retention
  policies; old data is removed via SQL `DELETE FROM ... WHERE time < ...` whenever
  desired. Raw data is kept indefinitely until deleted manually.
- Neutral, HA sensor ingestion starts "everything" — write all sensor state changes,
  prune entity allow/deny lists later once usage patterns are visible.
- Neutral, no community patterns to copy: kubesearch.dev has zero InfluxDB entries; only
  two community examples exist ([adampetrovic/home-ops](https://github.com/adampetrovic/home-ops)
  30 stars, InfluxDB 2.9;
  [gavinmcfall/home-ops](https://github.com/gavinmcfall/home-ops) 37 stars, 3 Enterprise).
- Bad, license dependency: Enterprise requires
  `INFLUXDB3_ENTERPRISE_LICENSE_TYPE=home` + `INFLUXDB3_ENTERPRISE_LICENSE_EMAIL`
  (secret) with one-time email verification; 2-CPU limit per cluster (set pod CPU
  limit accordingly; 2 cores is ample for sensor write volume).
- Bad, 2.x is the only fallback if the license flow proves annoying — 2.x is in maintenance mode upstream.

## Pros and Cons of the Options

### VictoriaMetrics / Thanos / Mimir (Prometheus-compatible long-term store)

Used via HA Prometheus endpoint + remote_write. Strong community support (well represented on kubesearch.dev), keeps one query language.

- Good, single TSDB ecosystem alongside existing kube-prometheus-stack
- Good, mature GitOps/homelab patterns and Helm charts
- Bad, HA→Prometheus path is numeric-only (no string attributes), needs a scrape/bridge hop — user requirement was one store for sensor data via the natural path
- Bad, built for cluster-metrics scale, not per-entity sensor telemetry

### Graphite

Listed in issue #39. Legacy carbon/aggregator stack.

- Good, classic time-series design
- Bad, no native HA integration — every path needs bridging
- Bad, effectively legacy upstream; no active development

### InfluxDB 1.x (official Helm chart)

The only chart the official `influxdata/helm-charts` repo provides.

- Good, official chart exists, HA integration supports it
- Bad, legacy product line, chart ships dated 1.8.10-alpine images

### InfluxDB 2.x

Maintenance-mode but stable; local PVC + embedded engine.

- Good, mature HA integration, no license/email dependency
- Bad, no new features upstream (maintenance mode)
- Bad, no official 2.x Helm chart — still app-template container

### InfluxDB 3 Core

MIT-licensed Rust rewrite, SQL, stateless-friendly.

- Bad, open-source tier caps queries at 72 hours range — defeats the entire use case
- Good, cleanest architecture of the OSS options

### InfluxDB 3 Enterprise

Full 3.x engine storing Parquet/Arrow in object storage.

- Good, unlimited query range; free "home" license tier with no expiry for home-sensor use
- Good, reuses existing MinIO as object store
- Bad, email verification + license env via secret; 2-CPU-per-cluster cap (cgroup-based, acceptable at sensor volumes)

## More Information

Decision captured from a structured grilling session, 2026-09-17:

| Decision     | Answer                                                       |
| ------------ | ------------------------------------------------------------ |
| Scope        | HA sensor data only, long-term storage                       |
| HA recorder  | Stays (parallel writes)                                      |
| Prometheus   | Stays (cluster metrics untouched)                            |
| Version      | InfluxDB 3 Enterprise, free home license                     |
| Object store | Existing MinIO                                               |
| Access       | Cluster-internal (ClusterIP), namespace `observability`      |
| Deploy       | bjw-s app-template container (no official chart for 2.x/3.x) |
| HA ingestion | Start with everything, prune later                           |
| Retention    | Raw indefinitely; delete via SQL when/if ever                |

Related community references:

- <https://github.com/adampetrovic/home-ops/blob/main/kubernetes/apps/observability/influxdb/app/helmrelease.yaml>
- <https://github.com/gavinmcfall/home-ops/blob/main/kubernetes/apps/database/influxdb3/app/helmrelease.yaml>
- <https://docs.influxdata.com/influxdb3/enterprise/about-the-home-license/>
- <https://docs.influxdata.com/influxdb3/core/query-data/delete/>
