# Konflate Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Konflate to the flux-system namespace for reviewing PRs on github://tyriis/home-ops

**Architecture:** OCIRepository source + HelmRelease with chartRef pattern (same as flux-operator), exposed via HTTPRoute at konflate.techtales.io through the envoy gateway.

**Tech Stack:** Flux CD (OCIRepository, HelmRelease, Kustomization), Helm chart from ghcr.io/home-operations/charts/konflate, Gateway API HTTPRoute

**Issue:** [#9364](https://github.com/tyriis/home-ops/issues/9364)
**Spec:** `docs/superpowers/specs/2026-06-25-konflate-design.md`

---

## File Structure

### New Files
- `kubernetes/main/apps/flux-system/konflate/flux-sync.yaml` — Kustomization CRD pointing at `./app/`
- `kubernetes/main/apps/flux-system/konflate/app/kustomization.yaml` — Lists resources
- `kubernetes/main/apps/flux-system/konflate/app/oci-repository.yaml` — OCIRepository for the Helm chart
- `kubernetes/main/apps/flux-system/konflate/app/helm-release.yaml` — HelmRelease with konflate values

### Modified Files
- `kubernetes/main/apps/flux-system/kustomization.yaml` — Add konflate/flux-sync.yaml to resources

---

### Task 1: Create flux-sync.yaml (Kustomization CRD)

**Files:**
- Create: `kubernetes/main/apps/flux-system/konflate/flux-sync.yaml`

- [ ] **Step 1: Create Kustomization CRD**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app konflate
  namespace: &namespace flux-system
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/flux-system/konflate/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: *namespace
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

- [ ] **Step 2: Create the directory and write the file**

Run:
```bash
mkdir -p kubernetes/main/apps/flux-system/konflate/app
```

Then write the content above to `kubernetes/main/apps/flux-system/konflate/flux-sync.yaml`.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/flux-system/konflate/flux-sync.yaml
git commit -m "feat(konflate): add flux-sync Kustomization CRD #9364"
```

---

### Task 2: Create OCIRepository for the Helm chart

**Files:**
- Create: `kubernetes/main/apps/flux-system/konflate/app/oci-repository.yaml`

- [ ] **Step 1: Create OCIRepository**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: konflate
spec:
  interval: 30m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  url: oci://ghcr.io/home-operations/charts/konflate
  ref:
    tag: 0.2.32
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/flux-system/konflate/app/oci-repository.yaml
git commit -m "feat(konflate): add OCIRepository source for Helm chart #9364"
```

---

### Task 3: Create HelmRelease with konflate configuration

**Files:**
- Create: `kubernetes/main/apps/flux-system/konflate/app/helm-release.yaml`

- [ ] **Step 1: Create HelmRelease**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: konflate
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: konflate
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
    config:
      repo: github://tyriis/home-ops
      statusChecks: true
      prComments: true
      publicUrl: https://konflate.techtales.io
    secret:
      existingSecret: konflate-secret
    httpRoute:
      enabled: true
      annotations:
        gatus.home-operations.com/endpoint: |-
          conditions: ["[STATUS] == 200"]
      parentRefs:
        - name: envoy
          namespace: networking
      hostnames:
        - konflate.techtales.io
    monitoring:
      serviceMonitor:
        enabled: true
    resources:
      requests:
        cpu: 50m
        memory: 256Mi
      limits:
        memory: 1Gi
```

Note: `secret.existingSecret` references `konflate-secret` which the user will create with the GitHub App credentials, webhook secret, etc.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/flux-system/konflate/app/helm-release.yaml
git commit -m "feat(konflate): add HelmRelease with config values #9364"
```

---

### Task 4: Create app kustomization.yaml

**Files:**
- Create: `kubernetes/main/apps/flux-system/konflate/app/kustomization.yaml`

- [ ] **Step 1: Create kustomization**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./oci-repository.yaml
  - ./helm-release.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/flux-system/konflate/app/kustomization.yaml
git commit -m "feat(konflate): add app kustomization listing resources #9364"
```

---

### Task 5: Wire konflate into flux-system kustomization

**Files:**
- Modify: `kubernetes/main/apps/flux-system/kustomization.yaml`

- [ ] **Step 1: Add konflate to resources**

Current resources:
```yaml
resources:
  - ./namespace.yaml
  - ./flux-instance/flux-sync.yaml
  - ./flux-operator/flux-sync.yaml
```

Add konflate:
```yaml
resources:
  - ./namespace.yaml
  - ./flux-instance/flux-sync.yaml
  - ./flux-operator/flux-sync.yaml
  - ./konflate/flux-sync.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/flux-system/kustomization.yaml
git commit -m "feat(konflate): wire konflate into flux-system kustomization #9364"
```
