# Migrate Mosquitto MQTT Broker from Raspberry Pi to the Main Kubernetes Cluster — Design Doc

**Date:** 2026-08-03
**Status:** Proposed
**Decision:** [ADR-0009](../../decisions/0009-migrate-mqtt-broker-from-raspberry-pi.md) (accepted)

## Overview

Migrate the standalone Mosquitto MQTT broker off a Raspberry Pi 1
(`mqtt.techtales.io` → `192.168.1.180`, single-instance, non-HA) into the main
Kubernetes cluster so it joins the same GitOps pipeline (Flux), secret store
(OpenBao `ExternalSecret`), observability stack (Loki/Prometheus), and deployment
mechanism as every one of its consumers. The Pi is the last
home-automation-critical service still running on bare metal outside the
GitOps-managed estate; this migration removes it entirely.

This spec documents the design in detail. The decision is recorded in ADR-0009
(status: `accepted`); this spec is `proposed` because implementation has not
started. An implementation plan will be written from this spec afterwards.

## Current State

| Component | File / Location | Key facts |
|---|---|---|
| Raspberry Pi broker | `mqtt.techtales.io` → `192.168.1.180` | Single-instance Mosquitto 1.4.14 on bare metal, plain MQTT 1883. `allow_anonymous` was unset (mosquitto 1.4.14 defaults to `true`), so anonymous clients (zigbee2mqtt, govee2mqtt) connected without credentials and the `passwd` file only authenticated the `homeassistant` user. Last home-automation-critical service outside the GitOps estate. |
| Consumer: zigbee2mqtt | `kubernetes/main/apps/home-automation/zigbee2mqtt/` | Connects to `mqtt.techtales.io:1883`. Main cluster, `home-automation` ns. |
| Consumer: govee2mqtt | `kubernetes/main/apps/home-automation/govee2mqtt/` | Connects to `mqtt.techtales.io:1883`. Main cluster, `home-automation` ns. |
| Consumer: ring-mqtt | `kubernetes/main/apps/home-automation/ring-mqtt/` | Connects to `mqtt.techtales.io:1883`. Main cluster, `home-automation` ns. |
| Consumer: Home Assistant | `kubernetes/main/apps/home-automation/home-assistant/` | Broker config in `tyriis/homeassistant-config` repo; connects via `mqtt.techtales.io:1883`. Main cluster, `home-automation` ns. |
| DNS endpoint | `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml` | `mqtt.techtales.io` A record (`~192.168.1.180`, lines ~76–98) to be re-pointed to `192.168.100.201`. `mqtt.lan` / `mqtt.home` CNAMEs untouched. |
| Cilium LB IPAM pool | `kubernetes/main/apps/kube-system/cilium/config/cilium-load-balancer-ip-pool.yaml` | `l2-pool`, `192.168.100.200–250`. Allocated: `.200` (envoy), `.202`/`.212` (minecraft), `.204` (syncthing), `.214` (hisense-aircon), `.215` (plex). `.201` is free → chosen for the broker. |
| House app pattern | `bjw-s/app-template` v5.0.1 (`bjw-s-charts` HelmRepository) | Used by `home-assistant`, `minecraft-java`, `syncthing`, `plex`. `flux-sync.yaml` with `postBuild.substitute` (`APP`/`NAMESPACE`/`CILIUM_LB_IPS`), `ExternalSecret` from OpenBao, `ceph-block` PVC. |
| Storage class | `ceph-block` (rook-ceph) | House standard for stateful workloads. Already running; not introduced for this workload. |
| Secret store | OpenBao `ClusterSecretStore` (`openbao-backend`) | Path convention `infra/kubernetes/main/home-automation/<app>`. Broker auth already lives here. |
| volsync component | `kubernetes/components/volsync/` | Restic + MinIO, default 2h schedule, OpenBao-stored creds. **NOT used** for this workload — broker state is recreatable, auth is backed up via OpenBao. |
| NAS-hosted MinIO | `docker/deploy/minio/` (doco-cd) | `minio.techtales.io` (TrueNAS), `minio.synlogy.techtales.io` (Synology). The only MinIO in the estate; relevant to the litestream analysis (reintroduces NAS dependency). |
| Backstage catalog | `.backstage/systems/mqtt.home/catalog-info.yaml` | "raspberry pi mosquitto mqtt broker" — to be updated post-migration. |

No Mosquitto/MQTT deployment exists anywhere in this repo (clusters or
`docker/`) — this is a greenfield migration.

## Critical Constraints

1. **DNS continuity is mandatory.** `mqtt.techtales.io` must keep resolving for
   consumers; only the A record target changes (`192.168.1.180` →
   `192.168.100.201`). `mqtt.lan` / `mqtt.home` CNAMEs are untouched. Consumers
   need zero reconfiguration.
2. **Envoy Gateway is HTTP/HTTPS-only.** TCP `1883` cannot be exposed through
   Envoy; it must use a Cilium `LoadBalancer` service with
   `lbipam.cilium.io/ips` — the established pattern for non-HTTP services
   (`minecraft-java`, `syncthing`, `plex`, `hisense-aircon`).
3. **Mosquitto 2.x uses SQLite** for `mosquitto.db` (retained messages,
   persistent sessions, in-flight QoS 1/2 queues). This raises a fair
   litestream-vs-ceph question, analysed in the Persistence section below.
4. **The only MinIO in the estate is NAS-hosted.** A litestream sidecar would
   reintroduce NAS uptime as a dependency on the broker's data path — the exact
   coupling the migration removes.
5. **All consumers run in the main cluster.** Placing the broker anywhere other
   than the main cluster splits the home-automation footprint across estates
   for no architectural benefit.
6. **Plain MQTT over 1883 on the LAN** is the current transport; TLS/MQTTS
   (`8883`) and WebSocket are out of scope (YAGNI for LAN-only).
7. **The only state that genuinely needs backup is the auth `passwd` file**, and
   that belongs in OpenBao (backed up by OpenBao), not in a broker PVC snapshot
   or a litestream replica. Retained messages and persistent sessions are
   recreatable by publishers within minutes.

## Approaches Considered

### Approach A — Main k8s cluster (Recommended)

Deploy `eclipse-mosquitto` (mosquitto 2.x, tag `2.0.22`, Renovate-managed
digests) via `bjw-s/app-template` v5.0.1 in the `home-automation` namespace,
`replicas: 1`.

- TCP `1883` exposed through a Cilium `LoadBalancer` service annotated
  `lbipam.cilium.io/ips: 192.168.100.201` (lowest free address in `l2-pool`).
- Auth: `allow_anonymous true`; `password_file` mounted from
  `mosquitto-secret`, an `ExternalSecret` synced from OpenBao at
  `infra/kubernetes/main/home-automation/mosquitto`, key `MOSQUITTO_PASSWD`
  holding the full `passwd` file content, mounted at
  `/mosquitto/config/passwd` via `subPath`. Anonymous clients (zigbee2mqtt,
  govee2mqtt) connect without credentials; the `passwd` file still authenticates
  the `homeassistant` user. This matches the Pi's effective behavior
  (mosquitto 1.4.14 defaulted `allow_anonymous` to true) and avoids breaking
  the existing consumer wiring; the broker is LAN-only with no TLS, so adding
  strict auth would be theatre without changing the real threat model.
- Config: `mosquitto.conf` ConfigMap — `listener 1883`, `persistence true`,
  `persistence_location /mosquitto/data/`,
  `password_file /mosquitto/config/passwd`.
- Persistence: `ceph-block` PVC for `/mosquitto/data/` (holds `mosquitto.db`).
  No `volsync` backup.
- Pod security: `runAsUser: 1883`, `readOnlyRootFilesystem: true` with the
  writable PVC at `/mosquitto/data/` and an `emptyDir` at `/tmp`.
- Container env: `TZ: Europe/Vienna` (repo convention, matches `n8n` and other
  home-automation apps) so log timestamps and any time-aware broker behavior
  line up with house local time.
- `flux-sync.yaml` with `postBuild.substitute`
  (`APP`/`CILIUM_LB_IPS`); `dependsOn`:
  `external-secrets-stores`, `rook-ceph-cluster`.

**Pros:**

- Same operational estate as every consumer — one GitOps pipeline, one secret
  store (OpenBao), one observability stack, one deployment mechanism; no new
  dependency on NAS uptime.
- Reuses the proven house pattern (`app-template` v5.0.1, `flux-sync.yaml` with
  `postBuild.substitute`, `ExternalSecret` from OpenBao, `ceph-block` PVC) —
  identical to `home-assistant`, `minecraft-java`, `syncthing`, `plex`.
- TCP exposure via Cilium `LoadBalancer` + `lbipam.cilium.io/ips` is the
  established pattern for non-HTTP services in this repo.
- A `Deployment` with `replicas: 1` on a multi-node cluster with `ceph-block`
  persistence is more available than the single Pi — k8s reschedules on node
  failure and the PVC survives.
- Secrets flow through OpenBao `ExternalSecret` (path
  `infra/kubernetes/main/home-automation/mosquitto`) — consistent with the rest
  of `home-automation/`.

**Cons:**

- The broker now depends on main-cluster health — a cluster-wide outage takes
  down home-automation messaging. Mitigated: all consumers are in-cluster
  anyway and would be down regardless.
- Introduces one more stateful workload on the cluster to maintain (image bumps,
  config drift) — offset by removing the Pi from the estate entirely.

### Approach B — Utility k8s cluster

Same `app-template` pattern on the single-node `util01` utility cluster
(`192.168.100.31`) that hosts Harbor, cert-manager, and OpenBao.

**Pros:**

- The utility cluster is infrastructure-focused and lightly loaded — the broker
  would not compete with noisy home-automation workloads.
- Same `app-template` pattern applies — no new tooling.

**Cons:**

- Every consumer lives in the main cluster — the broker would sit in a different
  GitOps estate, splitting the home-automation footprint across two clusters for
  no architectural benefit.
- The utility cluster is single-node (`util01`) — a single node failure takes the
  broker down with no reschedule alternative, which is worse than the
  multi-node main cluster.

**Verdict:** Rejected. Single-node availability is worse than the multi-node main
cluster, and splitting the home-automation footprint across two clusters gains
nothing.

### Approach C — NAS via doco-cd

Deploy `eclipse-mosquitto` via the `doco-cd` GitOps-for-docker tooling on a NAS
host, digest-pinned images Renovate-managed, secrets in SOPS-encrypted
`.sops.env`, persistence via named volumes or `${DATA_PATH}` bind mounts.

**Pros:**

- `doco-cd` is the established GitOps-for-docker tooling with digest-pinned
  images and SOPS-encrypted `.sops.env` — a clean, simple deployment model.
- A NAS host is independent of cluster control-plane health — decouples the
  broker from Kubernetes.
- Named volumes / `${DATA_PATH}` bind mounts give straightforward persistence.

**Cons:**

- All consumers are in the main cluster — the broker would sit outside the
  GitOps/Flux estate that runs every consumer, with a different secret store
  (SOPS vs OpenBao), a different observability stack, and a different deployment
  mechanism. It reintroduces the "one bare-metal service outside the estate"
  problem the migration is meant to solve.
- Adds a new dependency on NAS uptime for a home-automation-critical path — the
  broker is down whenever the NAS is down, even though every consumer is still
  up in the cluster.
- Backups would need a NAS-side story (ZFS snapshots) rather than the cluster's
  pipeline — a second backup mechanism for one workload.

**Verdict:** Rejected. Reintroduces a bare-metal service outside the GitOps estate
and a NAS-uptime dependency on a home-automation-critical path — the exact
coupling the migration removes.

## Comparison

| Dimension | A: Main k8s cluster | B: Utility k8s cluster | C: NAS via doco-cd |
|---|---|---|---|
| Same estate as consumers | yes | no (cross-cluster) | no (outside Flux estate) |
| House pattern (`app-template` + ESO + ceph) | yes | yes | no (doco-cd + SOPS) |
| Secret store | OpenBao `ExternalSecret` | OpenBao `ExternalSecret` | SOPS `.sops.env` |
| Observability stack | same as consumers | separate from consumers | separate from consumers |
| Availability vs Pi | better (multi-node reschedule) | worse (single-node `util01`) | same (NAS host uptime) |
| NAS-uptime dependency on critical path | none | none | yes (deciding drawback) |
| New tooling / Renovate deps | none (image only) | none (image only) | none (image only) |
| DNS continuity (re-point A record only) | yes | yes | yes |
| TCP 1883 exposure | Cilium LB IPAM `.201` | Cilium LB IPAM (util pool) | NAS host port |
| Backup story | OpenBao (auth); no volsync (state recreatable) | OpenBao (auth); no volsync | SOPS + ZFS snapshots (second mechanism) |
| Complexity | Low | Medium | Medium |
| Risk to existing setup | low | low | low |

## Recommendation

**Approach A — Main k8s cluster, single-instance Mosquitto via
`bjw-s/app-template` v5.0.1, with `ceph-block` PVC and no `volsync`.**

This keeps the broker in the same operational estate as every consumer
(zigbee2mqtt, govee2mqtt, ring-mqtt, Home Assistant all run in the main cluster)
and the same secret store (OpenBao already holds the broker's auth material),
reuses the proven house pattern (`app-template` + `ExternalSecret` + Cilium LB
IPAM + `ceph-block` PVC), and is already more available than the Pi: a
`Deployment` with `replicas: 1` is automatically rescheduled on node failure,
and the `ceph-block` PVC survives pod restarts. One GitOps estate, one
observability stack (Loki/Prometheus), one deployment mechanism — and no new
dependency on NAS uptime for a home-automation-critical path.

The broker image stays **`eclipse-mosquitto`** (single instance, mosquitto 2.x,
tag `2.0.22`, Renovate-managed digests). EMQX/VerneMQ clustering is not
warranted at this scale — a handful of LAN home-automation clients does not
justify a clustered broker, the operational complexity it adds, or the
divergence from the stable single-instance model the user values.
Single-instance Mosquitto on k8s already exceeds the Pi's availability.

TCP exposure uses a `type: LoadBalancer` service with
`lbipam.cilium.io/ips: 192.168.100.201` — the same pattern used by
`minecraft-java`, `syncthing`, `plex`, and Home Assistant's `hisense-aircon`
listener. Envoy Gateway is HTTP/HTTPS-only and is not used for MQTT.

**Choose Approach B instead if** the utility cluster were multi-node and you
wanted to isolate the broker from noisy home-automation workloads. It is not
multi-node, so don't.

**Choose Approach C instead if** you specifically wanted the broker decoupled
from Kubernetes control-plane health and were willing to accept a NAS-uptime
dependency on a home-automation-critical path plus a second secret store and
backup mechanism. The migration's whole motivation is to remove exactly that
coupling, so don't.

## Persistence: the SQLite / litestream question

Mosquitto 2.x stores its persistence DB (`mosquitto.db`) — retained messages,
persistent client sessions (`clean_session=false`), and in-flight QoS 1/2
queues — in **SQLite**. This raises a fair question: given it is SQLite, could a
**litestream** sidecar replicate it to S3-compatible storage (MinIO) and avoid a
`ceph-block` PVC entirely? The three sub-options below are analysed honestly,
then a recommendation is given.

### State that does NOT need broker-level backup

- `mosquitto.conf` — configuration. Declarative in Git (ConfigMap);
  version-controlled; no backup needed beyond Git.
- `passwd` / ACL files — authentication. Stored as a secret in OpenBao and
  synced via `ExternalSecret`. Backed up by OpenBao's own backup regime, not by
  the broker.
- **Retained messages** — recreatable. Home-automation publishers (zigbee2mqtt,
  govee2mqtt, HA, ring-mqtt) re-publish their retained topics shortly after the
  broker starts. Losing retained state means a brief window where subscribers
  see stale/missing values until the next publish — acceptable for a home lab.
- **Persistent client sessions** (`clean_session=false`) — recreatable. Clients
  reconnect and re-establish subscriptions. QoS 1/2 messages queued while a
  client was offline would be lost, but the current consumers reconnect cleanly.
- **In-flight QoS 1/2 message queues** — small and transient by definition.
  Acceptable to lose.

### State that genuinely needs backup

- The **auth/password file** — and that belongs in OpenBao (backed up by
  OpenBao), not in a broker PVC snapshot or a litestream replica.

### Sub-option A: `ceph-block` PVC (house standard) — Recommended

Mosquitto writes `mosquitto.db` to a `ceph-block` PVC; no `volsync` backup is
wired in (the state is recreatable).

- _Good:_ zero new tooling — `ceph-block` is the house storage class, already
  used by `home-assistant`, `minecraft-java`, `syncthing`, `plex`, and others.
  Adding the broker is a `StorageClass` line on a PVC manifest, not new
  infrastructure.
- _Good:_ `mosquitto.db` survives pod reschedules and node restarts — retained
  messages and persistent sessions are preserved across routine k8s churn.
- _Good:_ consistent with every other stateful app in the estate — one mental
  model, one storage class, one place to look.
- _Bad:_ depends on `rook-ceph` being healthy. Heavyweight for a tiny SQLite
  file — **but rook-ceph is already running as the house standard**, so using it
  adds no new operational burden. The "overkill" argument would hold if we were
  introducing ceph for this one workload; we are not.

### Sub-option B: litestream sidecar → NAS-hosted MinIO — Rejected

An `emptyDir` for the DB plus a litestream sidecar continuously replicating the
SQLite WAL to NAS-hosted MinIO, and a litestream `restore` initContainer running
before mosquitto starts.

- _Good:_ no `rook-ceph` dependency for the broker's data path.
- _Good:_ continuous WAL replication gives a better RPO than `volsync`'s 2h
  Restic schedule, and point-in-time recovery of retained messages.
- _Bad:_ **reintroduces NAS uptime as a dependency on the broker's data path** —
  the exact coupling the migration is removing. The only MinIO in the estate is
  NAS-hosted (`minio.techtales.io` on TrueNAS, `minio.synlogy.techtales.io` on
  Synology, deployed via `doco-cd` in `docker/deploy/minio/`); there is no
  in-cluster MinIO. If the NAS is down, litestream cannot replicate or restore.
- _Bad:_ the NAS-hosted MinIO is itself a single point of failure — litestream
  trades a cluster-internal dependency (ceph, multi-replicated) for an external
  one (NAS, single host).
- _Bad:_ two extra containers (sidecar + initContainer) and init-order
  complexity: the restore initContainer must complete before mosquitto starts,
  and the sidecar must stay healthy alongside the broker.
- _Bad:_ MinIO credentials become a new secret the broker needs in OpenBao, and
  the litestream image becomes a new Renovate-maintained dependency diverging
  from the house pattern.
- _Note the irony honestly:_ litestream removes ceph from the broker's data path
  but adds the NAS back to it — for a data path the broker arguably does not
  even need persisted (retained messages are recreatable, auth is in OpenBao).

### Sub-option C: no persistence at all (`emptyDir`) — Not chosen

`persistence: false`; the broker keeps retained/session state in memory. On
restart, retained topics are re-published by consumers within minutes and
sessions re-establish.

- _Good:_ zero storage dependency — no ceph, no MinIO, no litestream. The
  simplest possible option.
- _Good:_ matches the architect's own "state is recreatable" analysis: the only
  state that matters (auth) is in OpenBao, everything else is rebuilt by
  publishers within minutes.
- _Bad:_ a brief window of missing/stale retained values after every pod restart
  — subscribers see stale/missing values until the next publish. Acceptable per
  the analysis, but a real (if minor) UX cost on every restart.
- _Bad:_ if the broker ever runs multi-replica it breaks — irrelevant today
  (`replicas: 1`), but worth noting.

### Persistence recommendation

**Sub-option A: `ceph-block` PVC, no `volsync`.**

1. The architect's prior analysis stands: the only state that truly needs
   backing up is the auth `passwd` file, which already lives in OpenBao.
   Retained messages and persistent sessions are recreatable by publishers
   within minutes. So **no `volsync` backup is wired in** — this is the honest,
   non-over-engineered answer.
2. The user's instinct that ceph is "overkill for no reason" deserves a fair
   hearing — and the fair hearing is: ceph **is** heavyweight for a tiny SQLite
   file, **but it is already running as the house standard**. Using it for the
   broker adds a `StorageClass` line, not new infrastructure, new tooling, or a
   new Renovate dependency. The overkill argument would decide this if we were
   introducing ceph for this one workload; we are not.
3. Litestream genuinely **adds** a dependency (NAS-hosted MinIO) for a data path
   the broker does not even need persisted — and it is the exact NAS coupling
   the migration removes. It also adds two containers, init-order complexity, a
   new image to maintain, and a new secret. Net negative for this workload.
4. `emptyDir` is the simplest option and is internally consistent with the
   "state is recreatable" analysis, but ceph costs nothing extra here (it is
   already running) and surviving pod restarts is free insurance for retained
   messages — avoiding the brief stale-retained-value window on every restart.
   Given ceph is already the house standard, taking the free insurance is the
   more consistent choice.

## Security / Transport

- Keep **plain MQTT on `1883`** over the LAN for consumer compatibility
  (zigbee2mqtt, govee2mqtt, ring-mqtt, and HA all use plain MQTT today).
- `allow_anonymous true`; authentication via the `passwd` file delivered
  through `ExternalSecret` from OpenBao at
  `infra/kubernetes/main/home-automation/mosquitto`. Anonymous clients
  (zigbee2mqtt, govee2mqtt) connect without credentials; the `passwd` file
  still authenticates the `homeassistant` user. This matches the Pi's effective
  behavior (mosquitto 1.4.14 defaulted `allow_anonymous` to true); the broker
  is LAN-only with no TLS, so requiring auth from every client would break
  existing consumers without changing the real threat model.
- TLS / MQTTS (`8883`) and WebSocket listeners are deliberately out of scope for
  this migration (YAGNI for LAN-only); they can be added later behind a
  cert-manager certificate if external exposure is ever needed.
- The `passwd` file is the only state that genuinely needs backup, and it is
  backed up via OpenBao's own regime — not by a broker PVC snapshot or litestream.

## Target State

```
kubernetes/main/apps/home-automation/mosquitto/
├── flux-sync.yaml          # Kustomization CRD, postBuild.substitute {APP, CILIUM_LB_IPS}
└── app/
    ├── kustomization.yaml   # Lists resources
    ├── helm-release.yaml    # bjw-s/app-template v5.0.1, eclipse-mosquitto 2.0.22
    ├── external-secret.yaml # ExternalSecret → OpenBao infra/kubernetes/main/home-automation/mosquitto (MOSQUITTO_PASSWD)
    └── pvc.yaml             # ceph-block PVC for /mosquitto/data/
```

Plus a `ConfigMap` for `mosquitto.conf` (`listener 1883`, `persistence true`,
`persistence_location /mosquitto/data/`, `password_file /mosquitto/config/passwd`).

### Modified files

- `kubernetes/main/apps/home-automation/kustomization.yaml` — add
  `- ./mosquitto/flux-sync.yaml` to resources.
- `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml`
  — re-point `mqtt.techtales.io` A record `192.168.1.180` → `192.168.100.201`
  (lines ~76–98). `mqtt.lan` / `mqtt.home` CNAMEs untouched.
- `.backstage/systems/mqtt.home/catalog-info.yaml` — update description
  post-decommission (from "raspberry pi mosquitto mqtt broker" to reflect the
  k8s deployment).

### Out of band

- Pre-stage the Mosquitto `passwd` file contents in OpenBao at
  `infra/kubernetes/main/home-automation/mosquitto` (key `MOSQUITTO_PASSWD`).

## Rollout / Migration Order

1. **Pre-stage secret**: store the Mosquitto `passwd` file contents in OpenBao
   at `infra/kubernetes/main/home-automation/mosquitto` (key `MOSQUITTO_PASSWD`).
2. **Deploy broker**: add `kubernetes/main/apps/home-automation/mosquitto/`
   (`flux-sync.yaml` + `app/{kustomization.yaml, helm-release.yaml,
   external-secret.yaml, pvc.yaml}`), `CILIUM_LB_IPS: 192.168.100.201`,
   listener `1883`, `allow_anonymous true`, `password_file` from the
   `ExternalSecret`, `ceph-block` PVC for `mosquitto.db` (no `volsync`).
   `dependsOn`: `external-secrets-stores`, `rook-ceph-cluster`.
3. **Verify broker**: after Flux reconcile, confirm `192.168.100.201:1883` is
   reachable with `mosquitto_sub`/`mosquitto_pub` using the password file.
4. **Re-point DNS**: edit `dns-endpoint.yaml` — `mqtt.techtales.io` A record
   `192.168.1.180` → `192.168.100.201`. Keep `mqtt.lan` / `mqtt.home` CNAMEs.
5. **Verify consumers**: confirm zigbee2mqtt, govee2mqtt, ring-mqtt, and Home
   Assistant reconnect via `mqtt.techtales.io` (DNS TTL may cause a brief
   delay).
6. **Observe**: watch for 24–48h before decommissioning.
7. **Decommission Pi**: shut down Mosquitto on the Pi and remove the Pi from the
   estate. Update `.backstage/systems/mqtt.home/catalog-info.yaml`.
8. **Rollback**: revert the DNS A record to `192.168.1.180` (consumers reconnect
   to the Pi, which is still running until step 7) and
   `flux suspend kustomization mosquitto` until the issue is resolved.

## Out of Scope

- TLS / MQTTS (`8883`) and WebSocket listeners — YAGNI for LAN-only; can be added
  later behind a cert-manager certificate if external exposure is ever needed.
- EMQX/VerneMQ clustered broker — not warranted at this scale; single-instance
  Mosquitto on k8s already exceeds the Pi's availability.
- `volsync` backup — broker state is recreatable; the only state that matters
  (auth) is backed up via OpenBao.
- Litestream sidecar → NAS-hosted MinIO — reintroduces the NAS-uptime coupling
  the migration removes (see Persistence sub-option B).
- Multi-replica broker — `replicas: 1`; `emptyDir`/no-persistence would break
  under multi-replica, but `ceph-block` (RWO) keeps us honest here anyway.

## Open Questions for the User

1. Confirm `192.168.100.201` is still unallocated in `l2-pool` at deploy time
   (allocated IPs can drift as other LB services are added).
2. Confirm the `passwd` file content to store in OpenBao — copy it verbatim from
   the Pi (mosquitto 2.x `mosquitto_passwd` format), or regenerate fresh
   credentials and rotate consumers? (The latter is cleaner but requires
   touching each consumer's broker config.)
3. The Home Assistant broker config lives in the separate
   `tyriis/homeassistant-config` repo — confirm whether its `mqtt.techtales.io`
   reference needs any change beyond the DNS re-point (it should not, but worth a
   sanity check before step 5).
4. Backstage catalog `.backstage/systems/mqtt.home/catalog-info.yaml` currently
   describes "raspberry pi mosquitto mqtt broker" — confirm the desired
   post-migration description (e.g. "mosquitto mqtt broker on main k8s cluster")
   for the decommission step.

## References

- ADR: [docs/decisions/0009-migrate-mqtt-broker-from-raspberry-pi.md](../../decisions/0009-migrate-mqtt-broker-from-raspberry-pi.md)
- Reference apps: `kubernetes/main/apps/home-automation/home-assistant/`
  (stateful, LB service, `ExternalSecret`),
  `kubernetes/main/apps/gaming/minecraft-java/public-velocity-proxy/` (LB +
  `volsync`), `kubernetes/main/apps/default/podinfo/`.
- Cilium LB IPAM pool:
  `kubernetes/main/apps/kube-system/cilium/config/cilium-load-balancer-ip-pool.yaml`
  (`l2-pool`, `192.168.100.200–250`). Recommended IP `.201` is currently
  unallocated.
- DNS records:
  `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml`
  — `mqtt.techtales.io` A record (lines ~76–98) to be re-pointed from
  `192.168.1.180` to `192.168.100.201`; `mqtt.lan` / `mqtt.home` CNAMEs
  unchanged.
- Backups: `kubernetes/components/volsync/` (Restic + MinIO, default schedule
  every 2h, OpenBao-stored credentials) — **not used** for this workload.
- Secrets: OpenBao `ClusterSecretStore` (`openbao-backend`), path convention
  `infra/kubernetes/main/home-automation/<app>`.
- [bjw-s/app-template Helm Chart](https://bjw-s.github.io/helm-charts/docs/app-template/)
- [Eclipse Mosquitto](https://mosquitto.org/)