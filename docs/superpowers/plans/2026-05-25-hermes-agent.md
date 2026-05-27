# Hermes-Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy 4 isolated instances of hermes-agent (for tyriis, jazzlyn, crowlex, techinik) in a dedicated namespace with automated VolSync backups and strict NetworkPolicies.

**Architecture:** A DRY, parameterized approach where a single `app/helm-release.yaml` using `bjw-s/app-template` and a `network-policy.yaml` are instantiated four times via Flux Kustomization substitution.

**Tech Stack:** Kubernetes, Flux, Kustomize, bjw-s/app-template, VolSync, Cilium (NetworkPolicy).

---

### Task 1: Create Namespace and Base Kustomization

**Files:**

- Create: `kubernetes/main/apps/hermes-agent/namespace.yaml`
- Create: `kubernetes/main/apps/hermes-agent/kustomization.yaml`

- [ ] **Step 1: Write `namespace.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master/namespace.json
apiVersion: v1
kind: Namespace
metadata:
  name: hermes-agent
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
    volsync.backube/privileged-movers: "true"
```

- [ ] **Step 2: Write base `kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: hermes-agent
components:
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./flux-sync.yaml
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/namespace.yaml kubernetes/main/apps/hermes-agent/kustomization.yaml
git commit -m "feat: add hermes-agent namespace and base kustomization"
```

### Task 2: Create Parameterized App Configuration

**Files:**

- Create: `kubernetes/main/apps/hermes-agent/app/kustomization.yaml`
- Create: `kubernetes/main/apps/hermes-agent/app/helm-release.yaml`
- Create: `kubernetes/main/apps/hermes-agent/app/network-policy.yaml`

- [ ] **Step 1: Write `app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./helm-release.yaml
  - ./network-policy.yaml
```

- [ ] **Step 2: Write parameterized `app/helm-release.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app ${APP}
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
    global:
      createDefaultServiceAccount: false
    defaultPodOptions:
      securityContext:
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
    controllers:
      hermes:
        forceRename: *app
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: docker.io/nousresearch/hermes-agent
              tag: v2026.5.16@sha256:b6e41c155d6bfce5ad83c5d0fec670086db8a43250e4511c9474134be5482d33
            env:
              PORT: "8080"
            probes:
              liveness:
                enabled: true
              readiness:
                enabled: true
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 10m
              limits:
                memory: 1Gi
    service:
      app:
        forceRename: *app
        primary: true
        controller: hermes
        ports:
          http:
            port: 8080
    persistence:
      data:
        existingClaim: ${APP}-data
        advancedMounts:
          hermes:
            app:
              - path: /data
      tmp:
        type: emptyDir
        advancedMounts:
          hermes:
            app:
              - path: /tmp
```

- [ ] **Step 3: Write parameterized `app/network-policy.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master/networkpolicy.json
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${APP}-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ${APP}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow incoming traffic only from open-webui in the ai namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ai
          podSelector:
            matchLabels:
              app.kubernetes.io/name: open-webui
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow Internet egress but drop internal clusters to enforce isolation
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
```

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/app/kustomization.yaml kubernetes/main/apps/hermes-agent/app/helm-release.yaml kubernetes/main/apps/hermes-agent/app/network-policy.yaml
git commit -m "feat: add parameterized hermes-agent app and strict network policy"
```

### Task 3: Create Flux Sync Definitions for 4 Users

**Files:**

- Create: `kubernetes/main/apps/hermes-agent/flux-sync.yaml`

- [ ] **Step 1: Write `flux-sync.yaml`**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app hermes-agent-tyriis
spec:
  targetNamespace: hermes-agent
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/volsync
  path: ./kubernetes/main/apps/hermes-agent/app
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
    - name: volsync
      namespace: backup-system
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data

---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app hermes-agent-jazzlyn
spec:
  targetNamespace: hermes-agent
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/volsync
  path: ./kubernetes/main/apps/hermes-agent/app
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
    - name: volsync
      namespace: backup-system
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data

---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app hermes-agent-crowlex
spec:
  targetNamespace: hermes-agent
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/volsync
  path: ./kubernetes/main/apps/hermes-agent/app
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
    - name: volsync
      namespace: backup-system
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data

---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app hermes-agent-techinik
spec:
  targetNamespace: hermes-agent
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/volsync
  path: ./kubernetes/main/apps/hermes-agent/app
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
    - name: volsync
      namespace: backup-system
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/flux-sync.yaml
git commit -m "feat: add flux sync for 4 hermes-agent instances"
```
