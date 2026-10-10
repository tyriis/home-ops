---
status: proposed
date: 2026-10-11
decision-makers: [tyriis]
---

# Use VictoriaLogs single-node with vmauth per-unit keys as the central log platform

Related: ms01 (3-node Talos), utility (1-node Talos), Aostar NAS (TrueNAS), ZimaBoard, bifrost gateway, REMOTE site (UCG Ultra, DS218+) — all Tailscale-connected

## Context

Log collection today is fragmented. The community baseline (kubesearch.dev, checked 2026-10-10) has moved off promtail (deprecated by Grafana): victoria-logs-collector 57 repos, fluent-bit 37, promtail 33, Alloy 31, Loki 39. VictoriaLogs single-node is the de-facto homelab backend; its dominant deploy pattern is a single-replica StatefulSet, one PVC (`ceph-block` 20Gi, 14d retention modal). VictoriaLogs storage is local-disk only; object-storage tiering is open PR #1155 (no merged date, reads on cold data acknowledged-slow).

Goal: one central log sink for the whole estate (both clusters, NAS, bifrost, workstations, remote site) with per-unit credentials and hard-ish source attribution. Metrics stay out of scope (VictoriaMetrics side exists already; "logs only" decision made in-session).

## Requirements

| # | Requirement |
|---|-------------|
| R1 | Single central ingest+query endpoint for all units across both sites |
| R2 | Per-unit write credential (main cluster, workstation(s), NAS, bifrost, remote site); revocable independently |
| R3 | Hard source labeling: identity of writer enforced by the platform, not claimed by the client |
| R4 | Low ops burden on 1-node utility; no S3/MinIO dependency |
| R5 | Queryable from Grafana (datasource plugin) and CLI/vmui |
| R6 | Shippers tolerate utility restarts/network blips (buffer, don't drop silently) |
| R7 | Small footprint — utility is not a storage/IO-heavy node |

## Findings (source-checked 2026-10-10)

- **VL single-node**: one binary, one PVC (`-storageDataPath`), time-based retention, aggressive write compression (community: ~10-20x). Single-node takes tenant `0:0` only — multi-tenancy requires cluster mode (vlinsert/vmstorage/vmselect).
- **No native auth in VL** — authn/authz is entirely a reverse-proxy job.
- **vmauth** provides exactly the needed front door: per-user basic/bearer tokens, JWT, mTLS, TLS termination, per-user path allowlists (write-only keys can be locked to `/insert/*`), config hot-reload. One instance can front several backends (later: metrics too, config-compatible).
- **Tenancy-as-hard-labeling** (tenant per unit, enforced by proxy URL rewrite) is only available in **cluster mode**; on single-node it degrades to soft labels set by the shipper.
- **Ceph/RBD for log WAL** adds cross-node replication traffic per write; k8s@home uses it mostly by StorageClass gravity, not need. Log data is best-effort telemetry by everyone's model (0/100 repos run VL HA; nobody buffers re-collection beyond shipper-side).
- **Cluster mode cost** on a 1-node utility cluster: 3+ components + their PVCs, designed for multi-node scale-out — buys per-tenant retention/quotas, which at lab scale nobody uses.

## Options considered

| Option | R2 keys | R3 hard labels | R4/R7 ops+footprint | Verdict |
|---|---|---|---|---|
| A. Alloy + Loki on utility | ✓ (vmauth/reverse proxy) | ✗ labels client-set; Loki label-indexed, weak full-text | ingester memory + chunk/index storage + MinIO for real HA — heaviest ops | Standard Grafana path, but re-adopts the complexity the move is escaping |
| B. VL **cluster** + vmauth on utility | ✓ | ✓✓ tenant-per-unit, proxy-enforced; per-tenant retention | 3 components on a 1-node cluster; overprovisioned for lab ingest | The "hard labeling" purist answer; pays cluster tax for a feature set we won't use |
| C. VL single-node + vmauth per-unit keys (recommended) | ✓ vmauth users, write-only path-locked | ✓\* key proves writer identity; `host=`/`cluster=` labels shipper-set (soft in body) | 2 tiny deployments, 1-2 PVCs, no S3 | Meets R1-R7 at minimal cost; graduation path to B is vmauth-config-only |
| D. Stay per-cluster (VL on ms01 + scattered agents) | n/a | n/a | No central answer; NAS/workstations/remote have no sink | Fails R1 |
| E. Vector everywhere + VL | ✓ | same as C | Best pipeline language (VRL), but zero kubesearch traction, heavier agents; single backend already decided | No advantage over fluent-bit/vlagent at this scale |

\* Spoof window: a compromised unit could *claim* a different `host=` label inside its own insert stream. vmauth proves the key, not the payload. Accepted risk at homelab trust level (see Consequences for mitigation).

## Decision (proposed)

**Option C.** Deploy on **utility**:

1. `victoria-logs-single` (Flux HelmRelease), retention 30d, resources ~100m/512Mi requests.
2. `vmauth` in front; VL has no Ingress route — NetworkPolicy permits vmauth→VL only.
3. One vmauth user per unit, bearer token, `src_paths` locked to `/insert/*`; a separate read-only user (`/select/*`, `/api/v1/*`) for the Grafana plugin (`victoriametrics-logs-datasource`).
4. Shippers: fluent-bit or victoria-logs-collector DaemonSets per cluster unit, a node agent on NAS/workstations, remote site via Tailscale to the same endpoint. Each shipper sets `host=`/`cluster=` itself; tokens stored per-unit (Sops).
5. Shipper-side disk buffers on to satisfy R6.

Graduation trigger to Option B (vlcluster): need for true tenant isolation, per-unit retention/quota, or ingest beyond single-node comfort. vmauth config carries over unchanged (adds tenant path rewrite), Grafana source swap is a URL change.

## Open questions gating acceptance

1. **PVC placement:** local-disk StorageClass on the utility node (fastest, zero replication, data dies with disk, pod pinned) vs NFS→Aostar ZFS (snapshots, NAS redundancy, ingest crosses NFS). Working recommendation: local disk; logs are disposable by design.
2. **Endpoint exposure:** Envoy Gateway route with cert-manager TLS on LAN, or vmauth bound to Tailscale only (no Ingress, no LAN cert)? Remote site forces Tailscale either way; LAN workstations could ride the same tunnel.
3. **Shipper choice per unit:** victoria-logs-collector (native, minimal) vs fluent-bit (37-repo community precedent, JSON-line HTTP). Working recommendation: victoria-logs-collector on Talos nodes, fluent-bit where an agent already exists (NAS).
4. **Token hygiene:** rotate cadence + storage location (Sops per unit repo vs utility-sealed secret holding all).
5. **Grafana read path:** add read-only vmauth user now, or point Grafana at VL directly inside the utility cluster initially?

## Consequences (when accepted)

- utility gains a stateful, write-heavy-ish service — PVC sizing is trivial at this ingest (few GB / 30d) but needs a disk alert once.
- Spoof-window on labels (Option C footnote): acceptable because a compromised unit that forges labels can only pollute *its own stream's* history, and its key still can't write elsewhere. If this ever matters, Option B's tenants close it without rework.
- Single sink = single place to look when everything is broken, including when utility itself is. Node-local `journalctl` remains the escape hatch.
- PR #1155 (S3 tiering, still open, cold reads slow): revisit after merge only if long-term archive to NAS/DS218+ becomes a requirement.
- Metrics-on-the-same-front-door remains config-compatible: later means one more Deployment + vmauth user entries, no rework.

## Sources

- kubesearch.dev chart pages (2026-10-10): adoption counts; VL-single values survey (storageClass ceph-block 91/100, 20Gi 95, 14d 83, replicaCount set 1/100)
- VictoriaLogs docs: `-storageDataPath`, retention, single-node tenant 0:0, cluster components, Loki-API compat layer
- vmauth docs: per-user basic/bearer/JWT/mTLS, per-user `src_paths` URL allowlists, hot-reload
- VictoriaMetrics/victoria-logs issue #48 + PR #1155 (object-storage tiering, open, valyala requested changes, cold-read LRU-cache perf acknowledged)
- Grafana: victoriametrics-logs-datasource plugin (native LogsQL datasource)
