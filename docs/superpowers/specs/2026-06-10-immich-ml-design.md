# Immich ML Component Design

**Date:** 2026-06-10
**Scope:** Add machine-learning microservice to Immich deployment (main + devenv). Phase 3 of the Immich rollout.

**Issue:** #9048

---

## Overview

Add the `immich-machine-learning` container as a second controller in the existing bjw-s `app-template` HelmRelease. The server's `IMMICH_MACHINE_LEARNING_ENABLED` env var flips to `true` with an explicit URL to the ML service. ML model cache is persisted via a PVC to avoid re-downloading ~2-10GB of models on every restart.

---

## Main Cluster

### HelmRelease Changes (`kubernetes/main/apps/media/immich/app/helm-release.yaml`)

#### Server controller changes

| Env var | Old value | New value |
|---------|-----------|-----------|
| `IMMICH_MACHINE_LEARNING_ENABLED` | `"false"` | `"true"` |
| `IMMICH_MACHINE_LEARNING_URL` | *(absent)* | `http://immich-machine-learning.media.svc.cluster.local:3003` |

#### Machine-learning controller (new)

| Field | Value |
|-------|-------|
| Image | `ghcr.io/immich-app/immich-machine-learning` |
| Tag | `v2.7.5` (same tag as server; Renovate pins SHA) |
| Container port | 3003 |
| Probes | HTTP GET `/ping` on port 3003 (liveness + readiness), startup same |
| Env | `TRANSFORMERS_CACHE=/cache`, `HF_XET_CACHE=/cache/huggingface-xet`, `MPLCONFIGDIR=/cache/matplotlib-config` |
| Security context | Same as server (runAsNonRoot, readOnlyRootFilesystem, drop all) |
| Resources | Requests: 100m CPU, 512Mi memory |

#### Service (new)

```yaml
machine-learning:
  controller: machine-learning
  ports:
    http:
      port: 3003
```

#### Persistence (new)

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

### Files modified

- `kubernetes/main/apps/media/immich/app/helm-release.yaml` — add ML controller, service, persistence; update server env vars (main cluster uses inline env vars in helm-release, not a ConfigMap)

---

## Devenv

### HelmRelease Changes (`devenv/oci/apps/media/immich/app/helm-release.yaml`)

Same ML controller as main, with two differences:

| Field | Main | Devenv |
|-------|------|--------|
| `storageClass` | `ceph-block` | `standard` (kind local-path) |
| `IMMICH_MACHINE_LEARNING_URL` | Fully-qualified DNS | `http://immich-machine-learning.media.svc.cluster.local:3003` |

### Files modified

- `devenv/oci/apps/media/immich/app/helm-release.yaml`
- `devenv/oci/apps/media/immich/app/configuration.yaml` — add `IMMICH_MACHINE_LEARNING_ENABLED=true` + `IMMICH_MACHINE_LEARNING_URL=http://immich-machine-learning.media.svc.cluster.local:3003`

---

## Image Pinning

Use the **same image tag** as the server (`v2.7.5`). Renovate will pin the SHA digest automatically.

---

## Deployment Order

1. Merge ML changes (this PR)
2. Cluster syncs via Flux — ML pod starts, downloads models to PVC (~minutes)
3. Server flips ML to enabled — existing uploads trigger ML processing (smart search, face detection, OCR)

ML jobs for pre-existing assets can be triggered manually via the admin UI → Jobs panel.
