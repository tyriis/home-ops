---
status: accepted
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
- Fits existing infra: app-template deploy pattern, Ceph block storage with MinIO for backups, Grafana
  as single pane of glass
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
InfluxDB 3 variant without a query-range cap and Home Assistant can push sensor data
to it natively. It runs with a local `file` object store, so it needs no bucket and no S3
credentials; the free home licence is single-node, which leaves the engine's shared-object-store
multi-node design with nothing to buy here.

Placement: its own namespace `influxdb` on the main cluster (not `observability`), ClusterIP-only
(cluster-internal access), deployed with bjw-s app-template 5.3.0 as a plain container on image
`influxdb:3.12.2-enterprise`. The engine runs `--object-store=file --data-dir=/var/lib/influxdb3/data`
against the `influxdb3-data` PVC (20 Gi, `ceph-block`), created by the repo's volsync component. That
volume holds the WAL, the compacted Parquet files, the catalogue and the licence record, so it is the
dataset, and the component's nightly restic run (daily at 03:30 to stay clear of the two-hourly
fleet-wide slot) backs it up to MinIO. MinIO is therefore a backup target only. The official
`influxdata/helm-charts` chart `influxdb3-enterprise` (0.18.0) is multi-node and accepts only
`trial`/`commercial` licences, so it cannot run the free home licence, which is single-node only.
Reference implementation:
[gavinmcfall/home-ops](https://github.com/gavinmcfall/home-ops/blob/main/kubernetes/apps/database/influxdb3/app/helmrelease.yaml)
(37 stars).

The Home Assistant side is out of GitOps: HA's configuration lives on its own PVC, so the InfluxDB
integration is a documented UI step in the app README, not a manifest in this repository.

### Consequences

- Good, parallel data paths: Prometheus keeps cluster metrics; InfluxDB owns HA sensor data; Grafana queries both.
- Good, data durability: the whole dataset (WAL, Parquet, catalogue) sits on a replicated Ceph block
  volume and is snapshotted through Ceph and copied to MinIO by restic nightly, so a restore is a real
  recovery rather than a copy of scratch space.
- Good, read path: queries read Parquet from the block volume instead of fetching objects over HTTP
  from the NAS, which matters because the home licence caps the engine at two cores and one DataFusion
  thread shared by ingest, compaction and query.
- Neutral, capacity is a number instead of unlimited: 20 Gi covers years of sensor data at home
  cardinality and `ceph-block` expands online, but the volume needs watching rather than trusting an
  object store to grow without limit.
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

The legacy 1.x chart in the official `influxdata/helm-charts` repo, which otherwise ships 3.x.

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
- Good, reuses existing MinIO as the backup target, while the dataset itself runs on the cluster's own
  block storage
- Bad, email verification + license env via secret; 2-CPU-per-cluster cap (cgroup-based, acceptable at sensor volumes)

## More Information

Decision captured from a structured grilling session, 2026-09-17:

| Decision     | Answer                                                                 |
| ------------ | ---------------------------------------------------------------------- |
| Scope        | HA sensor data only, long-term storage                                 |
| HA recorder  | Stays (parallel writes)                                                |
| Prometheus   | Stays (cluster metrics untouched)                                      |
| Version      | InfluxDB 3 Enterprise, free home license                               |
| Object store | `ceph-block` PVC, `--object-store=file`; MinIO for restic only         |
| Access       | Cluster-internal (ClusterIP), namespace `influxdb`                     |
| Deploy       | bjw-s app-template; the official 3.x chart cannot run the home licence |
| HA ingestion | Start with everything, prune later                                     |
| Retention    | Raw indefinitely; delete via SQL when/if ever                          |

Related community references:

- <https://github.com/adampetrovic/home-ops/blob/main/kubernetes/apps/observability/influxdb/app/helmrelease.yaml>
- <https://github.com/gavinmcfall/home-ops/blob/main/kubernetes/apps/database/influxdb3/app/helmrelease.yaml>
- <https://docs.influxdata.com/influxdb3/enterprise/about-the-home-license/>
- <https://docs.influxdata.com/influxdb3/core/query-data/delete/>

## Revision history

- **2026-11-16**: the object store moved from MinIO to a local `file` object store on a 20 Gi
  `ceph-block` PVC, and MinIO was reduced to the restic backup target. This supersedes the earlier
  wording that placed the Parquet and catalog objects in MinIO as the source of truth, and drops the
  "S3-compatible object storage" prerequisite from the decision. Three reasons: the free home licence
  is single-node, so a shared object store bought no availability; the bucket had no backup of its
  own; and in that design the PVC held only scratch data, so the volsync backup could not rebuild
  anything. The option analysis above is left as originally written.
