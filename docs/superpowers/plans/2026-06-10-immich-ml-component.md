# Immich ML Component Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `machine-learning` controller to both main and devenv Immich HelmReleases, with PVC-backed model cache, and enable ML on the server.

**Architecture:** Add a second `machine-learning` controller (image `ghcr.io/immich-app/immich-machine-learning`) to the existing bjw-s `app-template` HelmRelease. The server controller gets `IMMICH_MACHINE_LEARNING_ENABLED=true` and an explicit ML URL. A 10Gi PVC (ceph-block main / standard devenv) is used for model cache at `/cache`.

**Tech Stack:** Flux CD, bjw-s app-template v5.0.1, Immich v2.7.5

**Spec:** `docs/superpowers/specs/2026-06-10-immich-ml-design.md`
**Issue:** #9048

---

## File Structure

### Files to modify (main cluster)

| File | Change |
|------|--------|
| `kubernetes/main/apps/media/immich/app/helm-release.yaml` | Add `machine-learning` controller, service, persistence; update server env vars |

### Files to modify (devenv)

| File | Change |
|------|--------|
| `devenv/oci/apps/media/immich/app/helm-release.yaml` | Add `machine-learning` controller, service, persistence |
| `devenv/oci/apps/media/immich/app/configuration.yaml` | Update env vars for ML |

---

## Task 1: Update main cluster HelmRelease

**File:** `kubernetes/main/apps/media/immich/app/helm-release.yaml`

- [ ] **Step 1: Update server controller env vars**

Change `IMMICH_MACHINE_LEARNING_ENABLED` from `"false"` to `"true"` and add `IMMICH_MACHINE_LEARNING_URL`:

```yaml
            env:
              DB_HOSTNAME: immich-db-rw.media.svc.cluster.local
              REDIS_HOSTNAME: dragonfly.dragonfly-system.svc.cluster.local
              IMMICH_MEDIA_LOCATION: /media
              IMMICH_MACHINE_LEARNING_ENABLED: "true"
              IMMICH_MACHINE_LEARNING_URL: http://immich-machine-learning.media.svc.cluster.local:3003
              IMMICH_SERVER_URL: https://immich.techtales.io
```

- [ ] **Step 2: Add machine-learning controller**

After the `server` controller block (after line 78, before `defaultPodOptions`), add:

```yaml
      machine-learning:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ghcr.io/immich-app/immich-machine-learning
              tag: v2.7.5
            env:
              TRANSFORMERS_CACHE: /cache
              HF_XET_CACHE: /cache/huggingface-xet
              MPLCONFIGDIR: /cache/matplotlib-config
            probes:
              liveness: &mlProbes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /ping
                    port: &mlPort 3003
                  initialDelaySeconds: 0
                  periodSeconds: 10
                  timeoutSeconds: 1
                  failureThreshold: 5
              readiness: *mlProbes
              startup:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /ping
                    port: *mlPort
                  failureThreshold: 30
                  periodSeconds: 5
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 100m
                memory: 512Mi
```

- [ ] **Step 3: Add machine-learning service**

After the `server` service block (after line 92), add:

```yaml
      machine-learning:
        controller: machine-learning
        ports:
          http:
            port: 3003
```

- [ ] **Step 4: Add ML cache persistence**

After the `tmpfs` persistence block (after line 128), add:

```yaml
      ml-cache:
        type: persistentVolumeClaim
        accessMode: ReadWriteOnce
        size: 10Gi
        storageClass: ceph-block
        advancedMounts:
          machine-learning:
            app:
              - path: /cache
```

- [ ] **Step 5: Validate with kustomize**

```bash
kustomize build kubernetes/main/apps/media/immich/app/
```

Expected: HelmRelease with server + machine-learning controllers, no errors.

- [ ] **Step 6: Commit**

```bash
git add kubernetes/main/apps/media/immich/app/helm-release.yaml
git commit -S -m "feat(main/immich): add machine-learning controller #9048"
```

---

## Task 2: Update devenv HelmRelease and config

**Files:**
- `devenv/oci/apps/media/immich/app/helm-release.yaml`
- `devenv/oci/apps/media/immich/app/configuration.yaml`

- [ ] **Step 1: Add machine-learning controller to devenv helm-release**

After the `dragonfly` controller block (after line 129), add:

```yaml
      machine-learning:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ghcr.io/immich-app/immich-machine-learning
              tag: v2.7.5
            env:
              TRANSFORMERS_CACHE: /cache
              HF_XET_CACHE: /cache/huggingface-xet
              MPLCONFIGDIR: /cache/matplotlib-config
            probes:
              liveness: &mlProbes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /ping
                    port: &mlPort 3003
                  initialDelaySeconds: 0
                  periodSeconds: 10
                  timeoutSeconds: 1
                  failureThreshold: 5
              readiness: *mlProbes
              startup:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /ping
                    port: *mlPort
                  failureThreshold: 30
                  periodSeconds: 5
            ports:
              - containerPort: 3003
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
```

- [ ] **Step 2: Add machine-learning service to devenv helm-release**

After the `dragonfly` service block (after line 146), add:

```yaml
      machine-learning:
        controller: machine-learning
        ports:
          http:
            port: 3003
```

- [ ] **Step 3: Add ML cache persistence to devenv helm-release**

After the `tmpfs` persistence block (after line 185), add:

```yaml
      ml-cache:
        type: persistentVolumeClaim
        accessMode: ReadWriteOnce
        size: 10Gi
        storageClass: standard
        advancedMounts:
          machine-learning:
            app:
              - path: /cache
```

- [ ] **Step 4: Update devenv configuration.yaml**

Change `IMMICH_MACHINE_LEARNING_ENABLED` to `"true"` and add `IMMICH_MACHINE_LEARNING_URL`:

```yaml
data:
  DB_HOSTNAME: immich-postgres
  REDIS_HOSTNAME: immich-dragonfly
  IMMICH_MEDIA_LOCATION: /media
  IMMICH_MACHINE_LEARNING_ENABLED: "true"
  IMMICH_MACHINE_LEARNING_URL: http://immich-machine-learning.media.svc.cluster.local:3003
```

- [ ] **Step 5: Validate with kustomize**

```bash
kustomize build devenv/oci/apps/media/immich/app/
```

Expected: ConfigMap, Secret, HelmRelease with all controllers, no errors.

- [ ] **Step 6: Commit**

```bash
git add devenv/oci/apps/media/immich/app/helm-release.yaml devenv/oci/apps/media/immich/app/configuration.yaml
git commit -S -m "feat(devenv/immich): add machine-learning controller #9048"
```
