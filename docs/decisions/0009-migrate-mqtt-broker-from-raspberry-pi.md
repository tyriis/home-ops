---
status: accepted
date: 2026-08-03
decision-makers: [tyriis]
---

<!-- markdownlint-disable MD013 -->

# Migrate MQTT broker from Raspberry Pi to the main Kubernetes cluster

## Context and Problem Statement

A standalone Mosquitto MQTT broker has run for years on a Raspberry Pi 1 at `mqtt.techtales.io` (A record `192.168.1.180`), in single-instance, non-HA mode.
It is stable, but it is the last home-automation-critical service still running on bare metal outside the GitOps-managed estate.

Consumers of the broker today are:

- `zigbee2mqtt` (port 1883)
- `govee2mqtt` (port 1883)
- `ring-mqtt`
- Home Assistant (broker config lives in the separate `tyriis/homeassistant-config` repo)

All consumers connect via the hostname `mqtt.techtales.io`; the A record is simply re-pointed when the broker moves, so consumers should not need reconfiguration.
No Mosquitto/MQTT deployment exists anywhere in this repo (clusters or `docker/`) — this is a greenfield migration.

The user explicitly asked: **what kind of backups does an MQTT broker actually need?** This decision records an honest, non-over-engineered answer rather than defaulting to "back up everything."

## Decision Drivers

- **DNS continuity**: `mqtt.techtales.io` must keep resolving for consumers; only the A record target changes.
- **Stability parity**: the Pi broker has been rock-solid; the replacement must be at least as reliable day-to-day.
- **GitOps alignment**: the deployment must be declarative in `tyriis/home-ops` and follow the existing house patterns.
- **Operational cohesion**: the broker should live in the same GitOps/Flux estate, the same secret store (OpenBao `ExternalSecret`), the same backup pipeline, and the same observability stack (Loki/Prometheus) as every consumer. It must not introduce a new dependency on NAS uptime for a home-automation-critical path. All consumers (zigbee2mqtt, govee2mqtt, ring-mqtt, Home Assistant) already run in the main cluster, and the broker's auth secret already lives in OpenBao — running the broker there means one estate to operate, one deployment mechanism, one place to look.
- **Honest backup posture**: do not over-engineer backups for state that is cheap to lose or already backed up elsewhere.
- **LAN-only transport**: current setup is plain MQTT over 1883 on the LAN; do not introduce TLS complexity unless warranted.

> Note on "latency": all devices share the same 2.5G LAN, so a cluster-hosted broker and a NAS-hosted broker differ by microseconds-vs-milliseconds at most. Latency is **not** a decision driver for a handful of home-automation MQTT clients and is not cited as a benefit below.

## Considered Options

- **Option 1: Main k8s cluster** (`kubernetes/main/apps/home-automation/mosquitto/`) — deploy `eclipse-mosquitto` via `bjw-s/app-template` v5.0.1, expose TCP 1883 through a Cilium `LoadBalancer` service using the `lbipam.cilium.io/ips` annotation, auth password file via `ExternalSecret` from OpenBao, `ceph-block` PVC for `mosquitto.db` (no `volsync` backup — state is recreatable).
- **Option 2: Utility k8s cluster** (`kubernetes/utility/apps/`) — same app-template pattern on the single-node `util01` cluster that hosts Harbor, cert-manager, and OpenBao.
- **Option 3: NAS via doco-cd** (`docker/deploy/mosquitto/`) — deploy via the `doco-cd` GitOps-for-docker tooling on a NAS host, secrets in SOPS-encrypted `.sops.env`, named volumes or `${DATA_PATH}` bind mounts.

## Decision Outcome

Chosen option: **Option 1: Main k8s cluster — single-instance Mosquitto via `bjw-s/app-template`.**

This keeps the broker in the same operational estate as every consumer (zigbee2mqtt, govee2mqtt, ring-mqtt, Home Assistant all run in the main cluster) and the same secret store (OpenBao already holds the broker's auth material), reuses the proven house pattern (`app-template` + `ExternalSecret` + Cilium LB IPAM + `ceph-block` PVC), and is already more available than the Pi: a Kubernetes `Deployment` with `replicas: 1` is automatically rescheduled on node failure, and the PVC (`ceph-block`) survives pod restarts. One GitOps estate, one observability stack (Loki/Prometheus), one deployment mechanism — and no new dependency on NAS uptime for a home-automation-critical path.

The broker image stays **`eclipse-mosquitto`** (single instance). EMQX/VerneMQ clustering is not warranted at this scale — a handful of LAN home-automation clients does not justify a clustered broker, the operational complexity it adds, or the divergence from the stable single-instance model the user values. Single-instance Mosquitto on k8s already exceeds the Pi's availability.

TCP exposure uses a `type: LoadBalancer` service with `lbipam.cilium.io/ips: ${CILIUM_LB_IPS}` — the same pattern used by `minecraft-java`, `syncthing`, `plex`, and Home Assistant's `hisense-aircon` listener. Envoy Gateway is HTTP/HTTPS-only and is not used for MQTT.

The recommended **LoadBalancer IP is `192.168.100.201`** — the lowest free address in the Cilium `l2-pool` (`192.168.100.200–250`). Currently allocated addresses are `.200` (envoy), `.202`/`.212` (minecraft), `.204` (syncthing), `.214` (hisense-aircon), `.215` (plex); `.201` is unused.

### Consequences

- _Good, because_ the broker lives in the same operational estate as every consumer — one GitOps pipeline (Flux), one secret store (OpenBao `ExternalSecret`), one observability stack (Loki/Prometheus), one deployment mechanism. No new dependency on NAS uptime for a home-automation-critical path.
- _Good, because_ the deployment follows the exact house pattern (`app-template` v5.0.1, `flux-sync.yaml` with `postBuild.substitute`, `ExternalSecret` from OpenBao, `ceph-block` PVC) — consistent with `home-assistant`, `minecraft-java`, `syncthing`, and `plex`.
- _Good, because_ a `Deployment` with `replicas: 1` plus a `ceph-block` PVC is already more available than the single Pi — Kubernetes reschedules on node failure and the persistence volume survives.
- _Good, because_ DNS continuity is preserved: only the `mqtt.techtales.io` A record in `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml` changes (`192.168.1.180` → `192.168.100.201`); the `mqtt.lan` / `mqtt.home` CNAMEs are untouched.
- _Good, because_ secrets (the Mosquitto `passwd` file) are managed by `ExternalSecret` from OpenBao at `infra/kubernetes/main/home-automation/mosquitto` — backed up as part of OpenBao, not the broker.
- _Neutral, because_ no `volsync` backup is wired in — the broker's state is recreatable (see "Persistence" below), and the only state that matters (auth) is already backed up via OpenBao.
- _Bad, because_ the broker now depends on the main cluster being healthy — a cluster-wide outage takes down home-automation messaging, whereas the Pi was independent. Mitigated by the cluster being the home of all consumers anyway (they would be down regardless).
- _Bad, because_ introduces one more stateful workload on the cluster to maintain (image bumps, config drift) — though this is offset by removing the Pi from the estate entirely.

### Persistence: what the broker's SQLite DB needs

Mosquitto 2.x stores its persistence DB (`mosquitto.db`) — retained messages, persistent client sessions (`clean_session=false`), and in-flight QoS 1/2 queues — in **SQLite**. This raises a fair question: given it is SQLite, could a **litestream** sidecar replicate it to S3-compatible storage (MinIO) and avoid a `rook-ceph` PVC entirely? The three sub-options below are analysed honestly, then a recommendation is given.

**State that does NOT need broker-level backup:**

- `mosquitto.conf` — configuration. Declarative in Git (ConfigMap). Version-controlled; no backup needed beyond Git.
- `passwd` / ACL files — authentication. Stored as a secret in OpenBao and synced via `ExternalSecret`. Backed up by OpenBao's own backup regime, not by the broker.
- **Retained messages** — recreatable. Home-automation publishers (zigbee2mqtt, govee2mqtt, HA, ring-mqtt) re-publish their retained topics shortly after the broker starts. Losing retained state means a brief window where subscribers see stale/missing values until the next publish — acceptable for a home lab.
- **Persistent client sessions** (`clean_session=false`) — recreatable. Clients reconnect and re-establish subscriptions. QoS 1/2 messages queued while a client was offline would be lost, but the current consumers reconnect cleanly.
- **In-flight QoS 1/2 message queues** — small and transient by definition. Acceptable to lose.

**State that genuinely needs backup:**

- The **auth/password file** — and that belongs in OpenBao (backed up by OpenBao), not in a broker PVC snapshot or a litestream replica.

#### Sub-option A: `ceph-block` PVC (house standard)

Mosquitto writes `mosquitto.db` to a `ceph-block` PVC; no `volsync` backup is wired in (the state is recreatable — see above).

- _Good, because_ zero new tooling — `ceph-block` is the house storage class, already used by `home-assistant`, `minecraft-java`, `syncthing`, `plex`, and others. Adding the broker is a `StorageClass` line on a PVC manifest, not new infrastructure.
- _Good, because_ `mosquitto.db` survives pod reschedules and node restarts — retained messages and persistent sessions are preserved across the kind of routine churn a k8s `Deployment` goes through.
- _Good, because_ consistent with every other stateful app in the estate — one mental model, one storage class, one place to look.
- _Bad, because_ depends on `rook-ceph` being healthy. This is a heavyweight dependency for a tiny SQLite file — **but rook-ceph is already running as the house standard**, so using it adds no new operational burden. The "overkill" argument would hold if we were introducing ceph for this one workload; we are not.

#### Sub-option B: litestream sidecar → MinIO (the user's idea)

An `emptyDir` for the DB plus a litestream sidecar continuously replicating the SQLite WAL to NAS-hosted MinIO, and a litestream `restore` initContainer running before mosquitto starts.

- _Good, because_ no `rook-ceph` dependency for the broker's data path.
- _Good, because_ continuous WAL replication gives a better RPO than `volsync`'s 2h Restic schedule, and point-in-time recovery of retained messages.
- _Bad, because_ **reintroduces NAS uptime as a dependency on the broker's data path** — the exact coupling the migration is removing. The only MinIO in the estate is NAS-hosted (`minio.techtales.io` on TrueNAS, `minio.synlogy.techtales.io` on Synology, deployed via `doco-cd` in `docker/deploy/minio/`); there is no in-cluster MinIO. If the NAS is down, litestream cannot replicate or restore.
- _Bad, because_ the NAS-hosted MinIO is itself a single point of failure — litestream trades a cluster-internal dependency (ceph, multi-replicated) for an external one (NAS, single host).
- _Bad, because_ two extra containers (sidecar + initContainer) and init-order complexity: the restore initContainer must complete before mosquitto starts, and the sidecar must stay healthy alongside the broker.
- _Bad, because_ MinIO credentials become a new secret the broker needs in OpenBao, and the litestream image becomes a new Renovate-maintained dependency diverging from the house pattern.
- _Note the irony honestly_: litestream removes ceph from the broker's data path but adds the NAS back to it — for a data path the broker arguably does not even need persisted (retained messages are recreatable, auth is in OpenBao).

#### Sub-option C: no persistence at all (`emptyDir`)

`persistence: false`; the broker keeps retained/session state in memory. On restart, retained topics are re-published by consumers (zigbee2mqtt, govee2mqtt, HA, ring-mqtt) within minutes and sessions re-establish.

- _Good, because_ zero storage dependency — no ceph, no MinIO, no litestream. The simplest possible option.
- _Good, because_ matches the architect's own "state is recreatable" analysis: the only state that matters (auth) is in OpenBao, everything else is rebuilt by publishers within minutes.
- _Bad, because_ a brief window of missing/stale retained values after every pod restart — subscribers see stale/missing values until the next publish. Acceptable per the analysis above, but a real (if minor) UX cost on every restart.
- _Bad, because_ if the broker ever runs multi-replica it breaks — irrelevant today (`replicas: 1`), but worth noting.

#### Persistence recommendation

**Sub-option A: `ceph-block` PVC, no `volsync`.**

Reasoning:

1. The architect's prior analysis stands: the only state that truly needs backing up is the auth `passwd` file, which already lives in OpenBao. Retained messages and persistent sessions are recreatable by publishers within minutes. So **no `volsync` backup is wired in** — this is the honest, non-over-engineered answer.
2. The user's instinct that ceph is "overkill for no reason" deserves a fair hearing — and the fair hearing is: ceph **is** heavyweight for a tiny SQLite file, **but it is already running as the house standard**. Using it for the broker adds a `StorageClass` line, not new infrastructure, new tooling, or a new Renovate dependency. The overkill argument would decide this if we were introducing ceph for this one workload; we are not.
3. Litestream genuinely **adds** a dependency (NAS-hosted MinIO) for a data path the broker does not even need persisted — and it is the exact NAS coupling the migration removes. It also adds two containers, init-order complexity, a new image to maintain, and a new secret. Net negative for this workload.
4. `emptyDir` is the simplest option and is internally consistent with the "state is recreatable" analysis, but ceph costs nothing extra here (it is already running) and surviving pod restarts is free insurance for retained messages — avoiding the brief stale-retained-value window on every restart. Given ceph is already the house standard, taking the free insurance is the more consistent choice.

This is a change from the previous draft of this ADR, which hedged with "optional `volsync` courtesy backup." The persistence sub-option analysis makes the case clearer: **`ceph-block` PVC for `mosquitto.db` persistence across pod restarts, and no `volsync` backup** — the state is recreatable, and the only state that matters (auth) is already backed up via OpenBao.

## Pros and Cons of the Options

### Option 1: Main k8s cluster (`kubernetes/main/apps/home-automation/mosquitto/`)

- Good, because same operational estate as every consumer (zigbee2mqtt, govee2mqtt, ring-mqtt, Home Assistant) — one GitOps pipeline, one secret store (OpenBao), one observability stack, one deployment mechanism; no new dependency on NAS uptime.
- Good, because reuses the proven house pattern: `bjw-s/app-template` v5.0.1, `flux-sync.yaml` with `postBuild.substitute` (`APP`/`NAMESPACE`/`CILIUM_LB_IPS`), `ExternalSecret` from OpenBao, `ceph-block` PVC — identical to `home-assistant`, `minecraft-java`, `syncthing`, `plex`.
- Good, because TCP exposure via Cilium `LoadBalancer` + `lbipam.cilium.io/ips` is the established pattern for non-HTTP services in this repo.
- Good, because a `Deployment` with `replicas: 1` on a multi-node cluster with `ceph-block` persistence is more available than the single Pi.
- Good, because secrets flow through OpenBao `ExternalSecret` (path `infra/kubernetes/main/home-automation/mosquitto`) — consistent with the rest of `home-automation/`.
- Neutral, because no `volsync` backup is wired in (broker state is recreatable; auth is backed up via OpenBao).
- Bad, because the broker depends on cluster health — a cluster-wide outage takes down home-automation messaging (mitigated: all consumers are in-cluster anyway).

### Option 2: Utility k8s cluster (`kubernetes/utility/apps/`)

- Good, because the utility cluster is infrastructure-focused and lightly loaded — the broker would not compete with noisy home-automation workloads.
- Good, because same `app-template` pattern applies — no new tooling.
- Bad, because every consumer lives in the main cluster — the broker would sit in a different GitOps estate, splitting the home-automation footprint across two clusters for no architectural benefit.
- Bad, because the utility cluster is single-node (`util01`, `192.168.100.31`) — a single node failure takes the broker down with no reschedule alternative, which is worse than the multi-node main cluster.

### Option 3: NAS via doco-cd (`docker/deploy/mosquitto/`)

- Good, because `doco-cd` is the established GitOps-for-docker tooling with digest-pinned images (Renovate-managed) and SOPS-encrypted `.sops.env` — a clean, simple deployment model.
- Good, because a NAS host is independent of cluster control-plane health — decouples the broker from Kubernetes.
- Good, because named volumes / `${DATA_PATH}` bind mounts give straightforward persistence.
- Neutral, because secrets use SOPS/age `.sops.env` rather than OpenBao `ExternalSecret` — consistent with the `docker/` estate but a different secret store from the cluster path.
- Bad, because all consumers are in the main cluster — the broker would sit outside the GitOps/Flux estate that runs every consumer, with a different secret store (SOPS vs OpenBao), a different observability stack, and a different deployment mechanism. It reintroduces the "one bare-metal service outside the estate" problem the migration is meant to solve.
- Bad, because it adds a new dependency on NAS uptime for a home-automation-critical path — the broker is down whenever the NAS is down, even though every consumer is still up in the cluster.
- Bad, because backups would need a NAS-side story (ZFS snapshots) rather than the cluster's pipeline — a second backup mechanism for one workload.

## More Information

- Reference apps: `kubernetes/main/apps/home-automation/home-assistant/` (stateful, LB service, `ExternalSecret`), `kubernetes/main/apps/gaming/minecraft-java/public-velocity-proxy/` (LB + `volsync`), `kubernetes/main/apps/default/podinfo/`.
- Cilium LB IPAM pool: `kubernetes/main/apps/kube-system/cilium/config/cilium-load-balancer-ip-pool.yaml` (`l2-pool`, `192.168.100.200–250`). Recommended IP `.201` is currently unallocated.
- DNS records: `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml` — `mqtt.techtales.io` A record (lines ~76-98) to be re-pointed from `192.168.1.180` to `192.168.100.201`; `mqtt.lan` / `mqtt.home` CNAMEs unchanged.
- Backups: `kubernetes/components/volsync/` (Restic + MinIO, default schedule every 2h, OpenBao-stored credentials) — **not used** for this workload; the broker's state is recreatable and the only state that matters (auth) is backed up via OpenBao. See "Persistence" above for the full analysis, including why a litestream→MinIO sidecar was considered and rejected.
- Secrets: OpenBao `ClusterSecretStore` (`openbao-backend`), path convention `infra/kubernetes/main/home-automation/<app>`.
- Backstage catalog: `.backstage/systems/mqtt.home/catalog-info.yaml` ("raspberry pi mosquitto mqtt broker") — to be updated post-migration.
- Broker image: `eclipse-mosquitto` (Helm chart `app-template` v5.0.1 from `bjw-s-charts` HelmRepository).
- [bjw-s/app-template Helm Chart](https://bjw-s.github.io/helm-charts/docs/app-template/)
- [Eclipse Mosquitto](https://mosquitto.org/)

### Migration plan sketch

1. **Pre-stage secret**: store the Mosquitto `passwd` file contents in OpenBao at `infra/kubernetes/main/home-automation/mosquitto`.
2. **Deploy broker**: add `kubernetes/main/apps/home-automation/mosquitto/` (`flux-sync.yaml` + `app/{kustomization.yaml, helm-release.yaml, external-secret.yaml, pvc.yaml}`), `CILIUM_LB_IPS: 192.168.100.201`, listener `1883`, `allow_anonymous false`, `password_file` from the `ExternalSecret`, `ceph-block` PVC for `mosquitto.db` (no `volsync`). `dependsOn`: `external-secrets-stores`, `rook-ceph-cluster`.
3. **Verify broker**: after Flux reconcile, confirm `192.168.100.201:1883` is reachable with `mosquitto_sub`/`mosquitto_pub` using the password file.
4. **Re-point DNS**: edit `dns-endpoint.yaml` — `mqtt.techtales.io` A record `192.168.1.180` → `192.168.100.201`. Keep `mqtt.lan` / `mqtt.home` CNAMEs.
5. **Verify consumers**: confirm zigbee2mqtt, govee2mqtt, ring-mqtt, and Home Assistant reconnect via `mqtt.techtales.io` (DNS TTL may cause a brief delay).
6. **Observe**: watch for 24–48h before decommissioning.
7. **Decommission Pi**: shut down Mosquitto on the Pi and remove the Pi from the estate.
8. **Rollback**: revert the DNS A record to `192.168.1.180` (consumers reconnect to the Pi, which is still running until step 7) and `flux suspend kustomization mosquitto` until the issue is resolved.

### Security / transport

- Keep **plain MQTT on `1883`** over the LAN for consumer compatibility (zigbee2mqtt, govee2mqtt, ring-mqtt, and HA all use plain MQTT today).
- `allow_anonymous false`; authentication via the `passwd` file delivered through `ExternalSecret`.
- TLS / MQTTS (`8883`) and WebSocket listeners are deliberately out of scope for this migration (YAGNI for LAN-only); they can be added later behind a cert-manager certificate if external exposure is ever needed.
