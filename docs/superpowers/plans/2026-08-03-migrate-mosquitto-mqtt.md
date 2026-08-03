# Migrate Mosquitto MQTT Broker to Main Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the standalone Mosquitto MQTT broker off the Raspberry Pi into the main Kubernetes cluster under `home-automation`, exposed on TCP 1883 via a Cilium LoadBalancer IP, with auth from OpenBao and a `ceph-block` PVC for persistence.

**Architecture:** Single-instance `eclipse-mosquitto` deployed with the `bjw-s` `app-template` Helm chart (v5.0.1) in the `home-automation` namespace. A `LoadBalancer` service with the `lbipam.cilium.io/ips` annotation claims `192.168.100.201` from the Cilium `l2-pool`. `mosquitto.conf` is delivered via a ConfigMap; the `passwd` auth file is delivered via an `ExternalSecret` from OpenBao (path `infra/kubernetes/main/home-automation/mosquitto`) and mounted as a file; `mosquitto.db` persistence lives on a `ceph-block` PVC. No `volsync` backup (state is recreatable; auth is backed up via OpenBao). DNS cutover is a separate commit so the broker can be verified before `mqtt.techtales.io` is re-pointed.

**Tech Stack:** Flux CD (Kustomization, HelmRelease, ExternalSecret), bjw-s app-template Helm chart v5.0.1, eclipse-mosquitto, Cilium LoadBalancer IPAM, ceph-block PVC, OpenBao

**Issue:** [#9869](https://github.com/tyriis/home-ops/issues/9869)
**Spec:** `docs/superpowers/specs/2026-08-03-migrate-mosquitto-mqtt-design.md`
**Decision:** `docs/decisions/0009-migrate-mqtt-broker-from-raspberry-pi.md`

---

## File Structure

### New Files
- `kubernetes/main/apps/home-automation/mosquitto/flux-sync.yaml` — Flux `Kustomization` CRD pointing at `./app/` (no volsync component; `dependsOn` external-secrets-stores + rook-ceph-cluster only)
- `kubernetes/main/apps/home-automation/mosquitto/app/kustomization.yaml` — Lists the app resources
- `kubernetes/main/apps/home-automation/mosquitto/app/configmap.yaml` — `mosquitto.conf` ConfigMap
- `kubernetes/main/apps/home-automation/mosquitto/app/external-secret.yaml` — `ExternalSecret` from OpenBao producing the `passwd` file content
- `kubernetes/main/apps/home-automation/mosquitto/app/pvc.yaml` — `ceph-block` PVC (`mosquitto-data`, 1Gi)
- `kubernetes/main/apps/home-automation/mosquitto/app/helm-release.yaml` — `app-template` v5.0.1 HelmRelease (LoadBalancer `.201`, ConfigMap + secret + PVC mounts, security context)

### Modified Files
- `kubernetes/main/apps/home-automation/kustomization.yaml` — Add `./mosquitto/flux-sync.yaml` to resources
- `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml` — Re-point `mqtt.techtales.io` A record `192.168.1.180` → `192.168.100.201` (CNAMEs untouched)

### Committed (decision record)
- `docs/decisions/0009-migrate-mqtt-broker-from-raspberry-pi.md` — The approved ADR (decision); already committed as docs(decision) — see commit f2b078265

---

## Notes & Assumptions

- **Image tag:** `eclipse-mosquitto` `2.0.22` is pinned by tag only (no digest). Renovate manages digest pinning on subsequent runs, consistent with the rest of the estate. Update to the current 2.x tag at implementation time if Renovate reports a newer one.
- **`passwd` mount approach:** The OpenBao secret at `infra/kubernetes/main/home-automation/mosquitto` is expected to hold a single key `MOSQUITTO_PASSWD` whose value is the full mosquitto `passwd` file content (e.g. `homeassistant:$6$...`). The `ExternalSecret` creates a Kubernetes `Secret` named `mosquitto-secret` with that key, and the Helm chart mounts it as a file at `/mosquitto/config/passwd` via `subPath: MOSQUITTO_PASSWD` (the same `type: secret` + `subPath` pattern used by `minecraft-public-velocity-proxy` `forwarding-secret` and `ring-mqtt` `credentials`). This keeps the auth file declarative, OpenBao-managed, and file-mounted without an initContainer.
- **Security context:** The official `eclipse-mosquitto` image runs as user `mosquitto` (UID 1883). `readOnlyRootFilesystem: true` is set; `/mosquitto/data` is the PVC and `/tmp` is an `emptyDir`, both writable.
- **No volsync:** Per the ADR, the broker's state is recreatable and the only state that matters (auth) is backed up via OpenBao. The `flux-sync.yaml` therefore omits the `components:` volsync line and the `VOLSYNC_SUFFIX` substitute, and `dependsOn` lists only `external-secrets-stores` and `rook-ceph-cluster`.
- **Pre-stage the OpenBao secret** before merging the broker manifests (see Task 9): the `ExternalSecret` will go `SecretSyncedError` until the key exists in OpenBao at `infra/kubernetes/main/home-automation/mosquitto`.

---

### Task 1: Create flux-sync.yaml (Flux Kustomization CRD)

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/flux-sync.yaml`

- [ ] **Step 1: Create the directory**

Run:
```bash
mkdir -p kubernetes/main/apps/home-automation/mosquitto/app
```

- [ ] **Step 2: Create the Flux Kustomization CRD**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/flux-sync.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app mosquitto
spec:
  targetNamespace: &namespace home-automation
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/home-automation/mosquitto/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: external-secrets-stores
      namespace: secops
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: *app
      CILIUM_LB_IPS: 192.168.100.201
```

Note: No `components:` line (no volsync) and no `VOLSYNC_SUFFIX` substitute — per the ADR, the broker's state is recreatable and auth is backed up via OpenBao.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/flux-sync.yaml
git commit -m "feat(mosquitto): add flux-sync Kustomization #9869"
```

---

### Task 2: Create mosquitto.conf ConfigMap

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/app/configmap.yaml`

- [ ] **Step 1: Create the ConfigMap**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/app/configmap.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.config.k8s.io/configmap_v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: mosquitto-config
data:
  mosquitto.conf: |
    # mosquitto.conf - managed by GitOps
    # Plain MQTT on the LAN; TLS/MQTTS is out of scope (see ADR 0009).
    per_listener_settings false
    listener 1883 0.0.0.0
    allow_anonymous true
    password_file /mosquitto/config/passwd
    persistence true
    persistence_location /mosquitto/data/
    autosave_interval 60
    # Disable Nagle on TCP: small MQTT control packets/publishes ship immediately
    # instead of being coalesced, which reduces latency on the LAN.
    set_tcp_nodelay true
    log_dest stdout
    log_type error
    log_type warning
    log_type notice
    log_type information
    connection_messages true
```

Note: `password_file` points at `/mosquitto/config/passwd`, which is the secret created in Task 3 and mounted in Task 5. `persistence_location` is the PVC mount path (Task 4). `allow_anonymous true` permits anonymous clients (zigbee2mqtt, govee2mqtt connect without credentials); `password_file` still authenticates the `homeassistant` user — matches the Pi's effective behavior (mosquitto 1.4.14 defaulted `allow_anonymous` to true). `autosave_interval 60` minimises retained-message loss on unclean restart.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/app/configmap.yaml
git commit -m "feat(mosquitto): add mosquitto.conf ConfigMap #9869"
```

---

### Task 3: Create ExternalSecret for the passwd file

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/app/external-secret.yaml`

- [ ] **Step 1: Create the ExternalSecret**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/app/external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name mosquitto-secret
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: openbao-backend
    kind: ClusterSecretStore
  target:
    name: *name
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        # Value is the full mosquitto passwd file content, e.g.:
        #   homeassistant:$6$...
        MOSQUITTO_PASSWD: "{{ .MOSQUITTO_PASSWD }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/home-automation/mosquitto
```

Note: The OpenBao secret at `infra/kubernetes/main/home-automation/mosquitto` must contain a key `MOSQUITTO_PASSWD` holding the full `passwd` file content (one or more `user:hash` lines). The resulting Kubernetes `Secret` `mosquitto-secret` is mounted as a file in Task 5 via `subPath: MOSQUITTO_PASSWD` → `/mosquitto/config/passwd`.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/app/external-secret.yaml
git commit -m "feat(mosquitto): add ExternalSecret for passwd file #9869"
```

---

### Task 4: Create ceph-block PVC

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/app/pvc.yaml`

- [ ] **Step 1: Create the PVC**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/app/pvc.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master/persistentvolumeclaim.json
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mosquitto-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ceph-block
```

Note: 1Gi is ample for `mosquitto.db` (retained messages + persistent sessions for a handful of LAN clients). No volsync backup is wired in — see ADR 0009 "Persistence".

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/app/pvc.yaml
git commit -m "feat(mosquitto): add ceph-block PVC for data #9869"
```

---

### Task 5: Create the HelmRelease (app-template v5.0.1)

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/app/helm-release.yaml`

- [ ] **Step 1: Create the HelmRelease**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/app/helm-release.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app mosquitto
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 5.0.1
      sourceRef:
        kind: HelmRepository
        name: bjw-s-charts
        namespace: flux-system
  install:
    remediation:
      retries: -1
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  uninstall:
    keepHistory: false
  values:
    controllers:
      mosquitto:
        replicas: 1
        annotations:
          reloader.stakater.com/auto: "true"
        pod:
          securityContext:
            runAsUser: 1883
            runAsGroup: 1883
            fsGroup: 1883
            fsGroupChangePolicy: OnRootMismatch
            seccompProfile:
              type: RuntimeDefault

        containers:
          app:
            image:
              # Renovate manages digest pinning on subsequent runs.
              repository: docker.io/library/eclipse-mosquitto
              tag: "2.0.22"
            env:
              TZ: Europe/Vienna
            ports:
              - name: mqtt
                containerPort: &port 1883
                protocol: TCP
            probes:
              readiness: &probes
                enabled: true
                type: TCP
                port: *port
              liveness: *probes
              startup:
                <<: *probes
                spec:
                  failureThreshold: 30
                  periodSeconds: 5
            resources:
              requests:
                cpu: 50m
                memory: 64Mi
              limits:
                memory: 128Mi
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL

    service:
      mqtt:
        controller: *app
        type: LoadBalancer
        annotations:
          lbipam.cilium.io/ips: ${CILIUM_LB_IPS}
        ports:
          mqtt:
            port: *port
            protocol: TCP
            targetPort: mqtt

    persistence:
      data:
        existingClaim: mosquitto-data
        globalMounts:
          - path: /mosquitto/data
      config:
        type: configMap
        name: mosquitto-config
        globalMounts:
          - path: /mosquitto/config/mosquitto.conf
            subPath: mosquitto.conf
            readOnly: true
      passwd:
        type: secret
        name: mosquitto-secret
        # 0440: readable by group 1883; 0600 would be root-only and crash mosquitto
        defaultMode: 0440
        globalMounts:
          - path: /mosquitto/config/passwd
            subPath: MOSQUITTO_PASSWD
            readOnly: true
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
```

Note:
- `runAsUser: 1883` matches the `mosquitto` user in the official image. `readOnlyRootFilesystem: true` is safe because `/mosquitto/data` (PVC) and `/tmp` (emptyDir) are writable.
- The `mqtt` service is `type: LoadBalancer` with `lbipam.cilium.io/ips: ${CILIUM_LB_IPS}` (substituted from `flux-sync.yaml` to `192.168.100.201`), mirroring the `minecraft-public-velocity-proxy` and `home-assistant` `hisense-aircon` patterns.
- `passwd` secret mount uses the `type: secret` + `subPath` pattern from `minecraft-public-velocity-proxy` (`forwarding-secret`) and `ring-mqtt` (`credentials`).
- Image tag is pinned to `2.0.22` without a digest; Renovate adds the `@sha256:...` digest on its next run, consistent with the estate's Renovate config.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/app/helm-release.yaml
git commit -m "feat(mosquitto): add app-template HelmRelease #9869"
```

---

### Task 6: Create app kustomization.yaml

**Files:**
- Create: `kubernetes/main/apps/home-automation/mosquitto/app/kustomization.yaml`

- [ ] **Step 1: Create the kustomization**

Write the following to `kubernetes/main/apps/home-automation/mosquitto/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: home-automation
resources:
  - ./configmap.yaml
  - ./external-secret.yaml
  - ./pvc.yaml
  - ./helm-release.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/mosquitto/app/kustomization.yaml
git commit -m "feat(mosquitto): add app kustomization listing resources #9869"
```

---

### Task 7: Wire mosquitto into the home-automation kustomization

**Files:**
- Modify: `kubernetes/main/apps/home-automation/kustomization.yaml`

- [ ] **Step 1: Add mosquitto to resources**

Current resources:
```yaml
resources:
  - ./namespace.yaml
  - ./esphome/flux-sync.yaml
  - ./govee2mqtt/flux-sync.yaml
  - ./home-assistant/flux-sync.yaml
  - ./locking-service/flux-sync.yaml
  # - ./matter-server/flux-sync.yaml needs additional network for pod
  - ./n8n/flux-sync.yaml
  - ./node-red/flux-sync.yaml
  - ./ring-mqtt/flux-sync.yaml
  - ./zigbee2mqtt/flux-sync.yaml
```

Add `./mosquitto/flux-sync.yaml` (place it after `locking-service` / before the commented `matter-server` line, matching the existing ordering):
```yaml
resources:
  - ./namespace.yaml
  - ./esphome/flux-sync.yaml
  - ./govee2mqtt/flux-sync.yaml
  - ./home-assistant/flux-sync.yaml
  - ./locking-service/flux-sync.yaml
  - ./mosquitto/flux-sync.yaml
  # - ./matter-server/flux-sync.yaml needs additional network for pod
  - ./n8n/flux-sync.yaml
  - ./node-red/flux-sync.yaml
  - ./ring-mqtt/flux-sync.yaml
  - ./zigbee2mqtt/flux-sync.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/home-automation/kustomization.yaml
git commit -m "feat(mosquitto): wire into home-automation kustomization #9869"
```

---

### Task 8: Re-point the mqtt.techtales.io A record

**Files:**
- Modify: `kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml`

This is a separate commit so the DNS cutover can be merged independently after the broker is verified reachable on `192.168.100.201:1883`.

- [ ] **Step 1: Update the A record target**

In the `mqtt-unifi` DNSEndpoint (lines ~76-98), change the `mqtt.techtales.io` A record target from `192.168.1.180` to `192.168.100.201`. Leave the `mqtt.lan` and `mqtt.home` CNAMEs untouched.

Before:
```yaml
  endpoints:
    - dnsName: mqtt.techtales.io
      recordType: A
      targets:
        - 192.168.1.180
    - dnsName: mqtt.lan
      recordType: CNAME
      targets:
        - mqtt.techtales.io
    - dnsName: mqtt.home
      recordType: CNAME
      targets:
        - mqtt.techtales.io
```

After:
```yaml
  endpoints:
    - dnsName: mqtt.techtales.io
      recordType: A
      targets:
        - 192.168.100.201
    - dnsName: mqtt.lan
      recordType: CNAME
      targets:
        - mqtt.techtales.io
    - dnsName: mqtt.home
      recordType: CNAME
      targets:
        - mqtt.techtales.io
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml
git commit -m "feat(dns): repoint mqtt A record to new broker IP #9869"
```

---

### Task 9: Verification

**Files:** none (verification only)

- [ ] **Step 1: Pre-stage the OpenBao secret**

Before Flux can reconcile the `ExternalSecret`, the key `MOSQUITTO_PASSWD` must exist in OpenBao at `infra/kubernetes/main/home-automation/mosquitto`. Generate the passwd file content on a host with the `mosquitto` client tools and store it in OpenBao:

```bash
# Generate a passwd entry for an existing or new user (run where mosquitto_passwd is available):
mosquitto_passwd -c -b /tmp/passwd homeassistant '<REDACTED_PASSWORD>'
# Inspect:
cat /tmp/passwd
# Store the file CONTENTS (not the path) as key MOSQUITTO_PASSWD in OpenBao at:
#   infra/kubernetes/main/home-automation/mosquitto
```

- [ ] **Step 2: Lint the new manifests**

Run the repo's linters (yamllint / MegaLinter via pre-commit) on the new and modified files:

```bash
pre-commit run --files \
  kubernetes/main/apps/home-automation/mosquitto/flux-sync.yaml \
  kubernetes/main/apps/home-automation/mosquitto/app/configmap.yaml \
  kubernetes/main/apps/home-automation/mosquitto/app/external-secret.yaml \
  kubernetes/main/apps/home-automation/mosquitto/app/pvc.yaml \
  kubernetes/main/apps/home-automation/mosquitto/app/helm-release.yaml \
  kubernetes/main/apps/home-automation/mosquitto/app/kustomization.yaml \
  kubernetes/main/apps/home-automation/kustomization.yaml \
  kubernetes/main/apps/networking/external-dns/unifi-records/dns-endpoint.yaml
```

- [ ] **Step 3: Server-side dry-run / validate**

After pushing, let Flux reconcile, then verify:

```bash
# Flux Kustomization health
flux get kustomization -n flux-system mosquitto

# ExternalSecret synced
kubectl get externalsecret -n home-automation mosquitto-secret -o yaml

# Pod running
kubectl get pods -n home-automation -l app.kubernetes.io/name=mosquitto

# LoadBalancer IP claimed
kubectl get svc -n home-automation mosquitto-mqtt

# Reachability + auth (from a host with mosquitto clients on the LAN)
# Authenticated path (homeassistant user via password_file)
mosquitto_sub -h 192.168.100.201 -p 1883 -u homeassistant -P '<REDACTED_PASSWORD>' -t 'home-ops/test' -C 1 &
mosquitto_pub -h 192.168.100.201 -p 1883 -u homeassistant -P '<REDACTED_PASSWORD>' -t 'home-ops/test' -m 'ok'
# Anonymous path (no -u/-P; exercises allow_anonymous true for zigbee2mqtt/govee2mqtt)
mosquitto_pub -h 192.168.100.201 -p 1883 -t 'home-ops/anon-test' -m 'ok'
```

- [ ] **Step 4: Post-DNS consumer verification**

After Task 8 is merged and DNS propagates (mind the TTL), confirm consumers reconnect via the hostname:

```bash
# zigbee2mqtt, govee2mqtt, ring-mqtt, Home Assistant logs should show a successful
# reconnect to mqtt.techtales.io:1883 within minutes.
kubectl logs -n home-automation -l app.kubernetes.io/name=zigbee2mqtt --tail=50 | grep -i mqtt
kubectl logs -n home-automation -l app.kubernetes.io/name=govee2mqtt --tail=50 | grep -i mqtt
kubectl logs -n home-automation -l app.kubernetes.io/name=ring-mqtt --tail=50 | grep -i mqtt
```

- [ ] **Step 5: Observe before decommissioning the Pi**

Watch for 24–48h before shutting down Mosquitto on the Raspberry Pi and removing the Pi from the estate. Rollback: revert the DNS A record to `192.168.1.180` (consumers reconnect to the Pi, which is still running until decommission) and `flux suspend kustomization mosquitto` until the issue is resolved.