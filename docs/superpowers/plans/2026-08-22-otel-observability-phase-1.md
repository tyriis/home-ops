# OpenTelemetry Observability Stack (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the OTel Operator + Collector (DaemonSet) with bearer-token OTLP ingress for local opencode (traces/logs/metrics), and Tempo (SingleBinary, S3-backed) — alongside the existing stack, without touching Promtail or Prometheus ServiceMonitors.

**Architecture:** Two new Flux apps (`opentelemetry/` and `tempo/`) in the `observability` namespace, mirroring the existing `loki` (OCI chart + `valuesFrom` S3) and `blackbox-exporter` (HTTPRoute) patterns. Collector ingests OTLP and exports traces→Tempo, logs→Loki (`/otlp`), metrics→Prometheus (native OTLP `/api/v1/otlp`). Prometheus gets an additive `enableOTLPReceiver`, Loki gets an additive `otlp_config`.

**Tech Stack:** Flux CD (Kustomization/HelmRelease/OCIRepository), opentelemetry-operator, OTel Collector (contrib), Tempo (grafana helm chart), MinIO S3, OpenBao + External Secrets Operator, Envoy Gateway (HTTPRoute), Grafana operator (GrafanaDatasource).

**Spec:** `docs/superpowers/specs/2026-08-12-otel-observability-design.md`

## Global Constraints

- GitOps-first: modify Flux manifests only; never `kubectl apply` changes directly.
- Namespace: `observability` (via `targetNamespace` in flux-sync, not `.metadata.namespace`).
- `dependsOn` namespaces: `cert-manager` → `cert-manager`; `external-secrets-stores` → `secops`; `kube-prometheus-stack`/`loki`/`opentelemetry-*`/`tempo` → `observability`; envoy gateway → `networking`.
- OpenBao secretStore: `secretStoreRef.name: openbao-backend`, `kind: ClusterSecretStore`; paths `infra/kubernetes/main/observability/<app>`.
- OCI charts use `OCIRepository` (with `layerSelector` mediaType `application/vnd.cncf.helm.chart.content.v1.tar+gzip`, `operation: copy`) + HelmRelease `chartRef` — NOT `chart.spec`.
- Pin exact `ref.tag` on OCIRepository (no `x` wildcards). Versions below are concrete; Renovate bumps them.
- `postBuild.substitute` is NOT used on the collector/tempo Kustomizations (no `FLUX_CLUSTER_NAME`) — so `${env:...}` in the collector CR stays literal.
- Commit messages follow conventional-commits (`feat(<scope>): ...`). Only commit on the feature branch; never `main`.
- Implementer is authorized/expected to adjust YAML formatting, add `#NOSONAR`/`#gitleaks:allow` comments, and fix schema/lint issues required to pass pre-commit/MegaLinter/kubeconform.

---

## File Structure

```
kubernetes/main/apps/observability/
├── kustomization.yaml                         [MODIFY] add opentelemetry + tempo flux-sync refs
├── opentelemetry/
│   ├── flux-sync.yaml                         [CREATE] 3 Kustomizations: operator, collector, observability
│   ├── operator/
│   │   ├── kustomization.yaml                 [CREATE]
│   │   ├── oci-repository.yaml                [CREATE]
│   │   └── helm-release.yaml                  [CREATE]
│   ├── collector/
│   │   ├── kustomization.yaml                 [CREATE]
│   │   ├── collector.yaml                     [CREATE] OpenTelemetryCollector CR (DaemonSet)
│   │   ├── external-secret.yaml               [CREATE] bearer token (OpenBao → Secret)
│   │   └── http-route.yaml                    [CREATE] HTTPRoute otel.techtales.io
│   └── observability/
│       ├── kustomization.yaml                 [CREATE]
│       └── service-monitor.yaml               [CREATE] collector self-monitoring :8888
├── tempo/
│   ├── flux-sync.yaml                         [CREATE] 2 Kustomizations: app, observability
│   ├── app/
│   │   ├── kustomization.yaml                 [CREATE]
│   │   ├── oci-repository.yaml                [CREATE]
│   │   ├── helm-release.yaml                  [CREATE] Tempo SingleBinary S3
│   │   └── external-secret.yaml               [CREATE] tempo-s3 (OpenBao → Secret)
│   └── observability/
│       ├── kustomization.yaml                 [CREATE]
│       └── service-monitor.yaml               [CREATE] Tempo self-monitoring
├── kube-prometheus-stack/app/helm-release.yaml [MODIFY] add enableOTLPReceiver
├── loki/app/helm-release.yaml                  [MODIFY] add otlp_config
└── grafana/instance/datasource.yaml            [MODIFY] add Tempo datasource
```

---

## Prerequisites (manual — before/alongside Tasks 2 and 4)

Outside Flux manifests; must exist before ExternalSecrets can sync.

- [ ] **MinIO `tempo` bucket**: create a `tempo` bucket (Terraform `terraform-minio` under `atlantis-system/techtales-io/`, or manual). Mirrors the existing `loki` bucket.
- [ ] **OpenBao secrets**:
  - `infra/kubernetes/main/observability/otel-collector` → key `OTEL_BEARER_TOKEN` (random token; the opencode client sends it as `Authorization: Bearer <token>`).
  - `infra/kubernetes/main/observability/tempo` → keys `S3_BUCKET_NAME`, `S3_BUCKET_HOST`, `S3_BUCKET_REGION`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` (scoped MinIO creds for the `tempo` bucket, mirroring `loki`).

---

## Task 1: opentelemetry-operator

**Files:**
- Create: `kubernetes/main/apps/observability/opentelemetry/flux-sync.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/operator/kustomization.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/operator/oci-repository.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/operator/helm-release.yaml`
- Modify: `kubernetes/main/apps/observability/kustomization.yaml`

**Interfaces:**
- Produces: Kustomization `opentelemetry-operator`, operator deployment + `opentelemetry.io/v1beta1` CRDs (consumed by Task 2's collector CR).

- [ ] **Step 1: Create `opentelemetry/flux-sync.yaml`** (operator Kustomization only — collector/observability docs added in Tasks 2–3)

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app opentelemetry-operator
spec:
  targetNamespace: &namespace observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/observability/opentelemetry/operator
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
    - name: cert-manager
      namespace: cert-manager
```

- [ ] **Step 2: Create `operator/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./oci-repository.yaml
  - ./helm-release.yaml
```

- [ ] **Step 3: Create `operator/oci-repository.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: opentelemetry-operator
spec:
  interval: 30m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  url: oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-operator
  ref:
    tag: 0.120.1
```

- [ ] **Step 4: Create `operator/helm-release.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: opentelemetry-operator
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: opentelemetry-operator
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
    # https://github.com/open-telemetry/opentelemetry-helm-charts
    admissionWebhooks:
      certManager:
        enabled: true
    manager:
      serviceMonitor:
        enabled: false
      resources:
        requests:
          cpu: 10m
          memory: 64Mi
```

> **Note:** verify exact chart value keys via `helm show values oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-operator --version 0.120.1` before finalizing; `admissionWebhooks.certManager.enabled` and `manager.resources` are the expected shapes.

- [ ] **Step 5: Register in parent kustomization** — add `- ./opentelemetry/flux-sync.yaml` between `./loki/flux-sync.yaml` and `./promtail/flux-sync.yaml`.

- [ ] **Step 6: Verify reconciliation**

```bash
kubectl kustomize kubernetes/main/apps/observability/opentelemetry/operator
flux get kustomization opentelemetry-operator
kubectl -n observability get pods -l app.kubernetes.io/name=opentelemetry-operator
kubectl get crd opentelemetrycollectors.opentelemetry.io
```

Expected: operator pod `Running`, `OpenTelemetryCollector` CRD present.

- [ ] **Step 7: Commit**

```bash
git add kubernetes/main/apps/observability/opentelemetry kubernetes/main/apps/observability/kustomization.yaml
git commit -m "feat(otel): add opentelemetry-operator"
```

## Task 2: opentelemetry-collector

**Files:**
- Modify: `kubernetes/main/apps/observability/opentelemetry/flux-sync.yaml` (append collector Kustomization)
- Create: `kubernetes/main/apps/observability/opentelemetry/collector/kustomization.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/collector/collector.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/collector/external-secret.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/collector/http-route.yaml`

**Interfaces:**
- Consumes: `opentelemetry-operator` (Task 1) for the CRD; `external-secrets-stores` (secops) for the bearer-token Secret; `loki-headless.observability.svc.cluster.local:3100`, `kube-prometheus-stack-prometheus.observability.svc:9090`, `tempo.observability.svc.cluster.local:4317` (Tempo from Task 4).
- Produces: DaemonSet `otel-collector`, Service `otel-collector-collector` (4318), Secret `otel-collector`, HTTPRoute `otel.techtales.io`.

- [ ] **Step 1: Append collector Kustomization to `flux-sync.yaml`** (second `---` document)

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app opentelemetry-collector
spec:
  targetNamespace: &namespace observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/observability/opentelemetry/collector
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
    - name: opentelemetry-operator
      namespace: *namespace
    - name: external-secrets-stores
      namespace: secops
```

- [ ] **Step 2: Create `collector/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./collector.yaml
  - ./external-secret.yaml
  - ./http-route.yaml
```

- [ ] **Step 3: Create `collector/collector.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/opentelemetry.io/opentelemetrycollector_v1beta1.json
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
spec:
  mode: daemonset
  image: otel/opentelemetry-collector-contrib:0.158.0
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
            auth:
              authenticator: bearertokenauth
          http:
            endpoint: 0.0.0.0:4318
            auth:
              authenticator: bearertokenauth
    processors:
      batch:
        send_batch_size: 1024
        timeout: 1s
      memory_limiter:
        check_interval: 5s
        limit_mib: 1024
    exporters:
      otlphttp/prom:
        endpoint: http://kube-prometheus-stack-prometheus.observability.svc:9090/api/v1/otlp
        tls:
          insecure: true
      otlphttp/loki:
        endpoint: http://loki-headless.observability.svc.cluster.local:3100/otlp
        tls:
          insecure: true
      otlp/tempo:
        endpoint: tempo.observability.svc.cluster.local:4317
        tls:
          insecure: true
    extensions:
      health_check: {}
      bearertokenauth:
        scheme: Bearer
        token: ${env:OTEL_BEARER_TOKEN}
    service:
      extensions: [health_check, bearertokenauth]
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlphttp/prom]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [otlphttp/loki]
      telemetry:
        metrics:
          address: 0.0.0.0:8888
  env:
    - name: OTEL_BEARER_TOKEN
      valueFrom:
        secretKeyRef:
          name: otel-collector
          key: OTEL_BEARER_TOKEN
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 1Gi
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    fsGroup: 65532
    readOnlyRootFilesystem: true
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop: [ALL]
```

- [ ] **Step 4: Create `collector/external-secret.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name otel-collector
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
        OTEL_BEARER_TOKEN: "{{ .OTEL_BEARER_TOKEN }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/observability/otel-collector #gitleaks:allow
```

- [ ] **Step 5: Create `collector/http-route.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: otel-collector
  annotations:
    external-dns/unifi: "true"
    gatus.home-operations.com/endpoint: |
      name: otel-collector
      headers:
        Authorization: Bearer ${OTEL_BEARER_TOKEN}
spec:
  hostnames:
    - otel.techtales.io
  parentRefs:
    - name: envoy
      namespace: networking
      sectionName: https
  rules:
    - backendRefs:
        - name: otel-collector-collector
          port: 4318
      matches:
        - path:
            type: PathPrefix
            value: /
```

> **Note:** the operator creates Service `otel-collector-collector` for the collector. If the port differs at reconcile time, confirm with `kubectl -n observability get svc otel-collector-collector -o yaml` and adjust `backendRefs[].port`.

- [ ] **Step 6: Verify**

```bash
kubectl kustomize kubernetes/main/apps/observability/opentelemetry/collector
flux get kustomization opentelemetry-collector
kubectl -n observability get pods -l app.kubernetes.io/name=otel-collector
kubectl -n observability get externalsecret otel-collector
```

Expected: DaemonSet pods `Running` on all nodes; `otel-collector` Secret `SecretSynced`.

- [ ] **Step 7: Commit**

```bash
git add kubernetes/main/apps/observability/opentelemetry
git commit -m "feat(otel): add opentelemetry-collector daemonset"
```

---

## Task 3: opentelemetry-observability

**Files:**
- Modify: `kubernetes/main/apps/observability/opentelemetry/flux-sync.yaml` (append observability Kustomization)
- Create: `kubernetes/main/apps/observability/opentelemetry/observability/kustomization.yaml`
- Create: `kubernetes/main/apps/observability/opentelemetry/observability/service-monitor.yaml`

**Interfaces:**
- Consumes: `opentelemetry-operator` + `kube-prometheus-stack` (ServiceMonitor CRD) for `dependsOn`.
- Produces: ServiceMonitor `otel-collector` scraping collector internal metrics on 8888.

- [ ] **Step 1: Append observability Kustomization to `flux-sync.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app opentelemetry-observability
spec:
  targetNamespace: &namespace observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/observability/opentelemetry/observability
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
    - name: opentelemetry-operator
      namespace: *namespace
    - name: kube-prometheus-stack
      namespace: *namespace
```

- [ ] **Step 2: Create `observability/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./service-monitor.yaml
```

- [ ] **Step 3: Create `observability/service-monitor.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/servicemonitor_v1.json
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: otel-collector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: otel-collector
      app.kubernetes.io/managed-by: opentelemetry-operator
  endpoints:
    - targetPort: 8888
      interval: 30s
      path: /metrics
```

> **Note:** verify the operator's pod labels and the metrics port name with `kubectl -n observability get pods -l app.kubernetes.io/managed-by=opentelemetry-operator --show-labels` and `kubectl -n observability get svc otel-collector-collector -o yaml`. Adjust `selector.matchLabels` and `targetPort` if they differ. Fallback: set `spec.observability.metrics.enableMetricsUsingServiceMonitors: true` on the collector CR and drop this hand-rolled file.

- [ ] **Step 4: Verify**

```bash
kubectl kustomize kubernetes/main/apps/observability/opentelemetry/observability
flux get kustomization opentelemetry-observability
kubectl -n observability get servicemonitor otel-collector
```

Expected: ServiceMonitor `otel-collector` present; Prometheus target `otel-collector` (port 8888) up.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/observability/opentelemetry
git commit -m "feat(otel): add opentelemetry-collector service monitor"
```

## Task 4: tempo app

**Files:**
- Create: `kubernetes/main/apps/observability/tempo/flux-sync.yaml`
- Create: `kubernetes/main/apps/observability/tempo/app/kustomization.yaml`
- Create: `kubernetes/main/apps/observability/tempo/app/oci-repository.yaml`
- Create: `kubernetes/main/apps/observability/tempo/app/helm-release.yaml`
- Create: `kubernetes/main/apps/observability/tempo/app/external-secret.yaml`
- Modify: `kubernetes/main/apps/observability/kustomization.yaml`

**Interfaces:**
- Consumes: `external-secrets-stores` (secops) for the S3 Secret; MinIO `tempo` bucket (prerequisite).
- Produces: Tempo SingleBinary deployment, Service `tempo` (ports 4317/4318 OTLP, 3200 query), Secret `tempo-s3`.

- [ ] **Step 1: Create `tempo/flux-sync.yaml`** (app Kustomization only — observability doc added in Task 5)

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app tempo
spec:
  targetNamespace: &namespace observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/observability/tempo/app
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
```

- [ ] **Step 2: Create `app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./oci-repository.yaml
  - ./helm-release.yaml
  - ./external-secret.yaml
```

- [ ] **Step 3: Create `app/oci-repository.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: tempo
spec:
  interval: 30m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  url: oci://ghcr.io/grafana/helm-charts/tempo
  ref:
    tag: 1.24.4
```

- [ ] **Step 4: Create `app/external-secret.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name tempo-s3
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
        S3_BUCKET_NAME: "{{ .S3_BUCKET_NAME }}"
        S3_BUCKET_HOST: "{{ .S3_BUCKET_HOST }}"
        S3_BUCKET_REGION: "{{ .S3_BUCKET_REGION }}"
        S3_ACCESS_KEY: "{{ .S3_ACCESS_KEY }}"
        S3_SECRET_KEY: "{{ .S3_SECRET_KEY }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/observability/tempo #gitleaks:allow
```

- [ ] **Step 5: Create `app/helm-release.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tempo
spec:
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: tempo
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
    # https://artifacthub.io/packages/helm/grafana/tempo?modal=values
    fullnameOverride: tempo
    tempo:
      usage_report:
        reporting_enabled: false
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"
      storage:
        trace:
          backend: s3
          s3:
            bucket: tempo
            forcepathstyle: true
            insecure: true
      metricsGenerator:
        enabled: false
    serviceMonitor:
      enabled: false
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 2Gi
  valuesFrom:
    - kind: Secret
      name: tempo-s3
      valuesKey: S3_BUCKET_NAME
      targetPath: tempo.storage.trace.s3.bucket
    - kind: Secret
      name: tempo-s3
      valuesKey: S3_BUCKET_HOST
      targetPath: tempo.storage.trace.s3.endpoint
    - kind: Secret
      name: tempo-s3
      valuesKey: S3_BUCKET_REGION
      targetPath: tempo.storage.trace.s3.region
    - kind: Secret
      name: tempo-s3
      valuesKey: S3_ACCESS_KEY
      targetPath: tempo.storage.trace.s3.access_key
    - kind: Secret
      name: tempo-s3
      valuesKey: S3_SECRET_KEY
      targetPath: tempo.storage.trace.s3.secret_key
```

> **Note:** verify exact chart keys via `helm show values oci://ghcr.io/grafana/helm-charts/tempo --version 1.24.4`. The `tempo.storage.trace.s3.*` and `tempo.receivers.otlp.protocols.*` paths are the expected shapes; `usage_report.reporting_enabled` disables telemetry. `metricsGenerator.enabled: false` keeps span-metrics deferred (Phase 2).

- [ ] **Step 6: Register in parent kustomization** — add `- ./tempo/flux-sync.yaml` between `./speedtest-exporter/flux-sync.yaml` and `./unpoller/flux-sync.yaml`.

- [ ] **Step 7: Verify**

```bash
kubectl kustomize kubernetes/main/apps/observability/tempo/app
flux get kustomization tempo
kubectl -n observability get pods -l app.kubernetes.io/name=tempo
kubectl -n observability get externalsecret tempo-s3
```

Expected: Tempo pod `Running`; `tempo-s3` Secret `SecretSynced`.

- [ ] **Step 8: Commit**

```bash
git add kubernetes/main/apps/observability/tempo kubernetes/main/apps/observability/kustomization.yaml
git commit -m "feat(tempo): add tempo tracing backend"
```

---

## Task 5: tempo-observability

**Files:**
- Modify: `kubernetes/main/apps/observability/tempo/flux-sync.yaml` (append observability Kustomization)
- Create: `kubernetes/main/apps/observability/tempo/observability/kustomization.yaml`
- Create: `kubernetes/main/apps/observability/tempo/observability/service-monitor.yaml`

**Interfaces:**
- Consumes: `tempo` app (Task 4) + `kube-prometheus-stack` (ServiceMonitor CRD) for `dependsOn`.
- Produces: ServiceMonitor `tempo` scraping Tempo self-metrics.

- [ ] **Step 1: Append observability Kustomization to `flux-sync.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app tempo-observability
spec:
  targetNamespace: &namespace observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/observability/tempo/observability
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
    - name: tempo
      namespace: *namespace
    - name: kube-prometheus-stack
      namespace: *namespace
```

- [ ] **Step 2: Create `observability/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./service-monitor.yaml
```

- [ ] **Step 3: Create `observability/service-monitor.yaml`**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/monitoring.coreos.com/servicemonitor_v1.json
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tempo
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: tempo
  endpoints:
    - port: http-metrics
      interval: 30s
      path: /metrics
```

> **Note:** verify Tempo's metrics port name/number with `kubectl -n observability get svc tempo -o yaml` (single-binary exposes metrics on the `http-metrics`/`3100` server port). Adjust `endpoints[].port` if the port name differs.

- [ ] **Step 4: Verify**

```bash
kubectl kustomize kubernetes/main/apps/observability/tempo/observability
flux get kustomization tempo-observability
kubectl -n observability get servicemonitor tempo
```

Expected: ServiceMonitor `tempo` present; Prometheus target `tempo` up.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/observability/tempo
git commit -m "feat(tempo): add tempo service monitor"
```

## Task 6: kube-prometheus-stack — enable native OTLP receiver

**Files:**
- Modify: `kubernetes/main/apps/observability/kube-prometheus-stack/app/helm-release.yaml`

**Interfaces:**
- Produces: Prometheus `--web.enable-otlp-receiver`, serving `/api/v1/otlp/v1/metrics` (consumed by the collector's `otlphttp/prom` exporter).

- [ ] **Step 1: Add `enableOTLPReceiver: true` under `prometheusSpec:`** — insert after `enableFeatures` (currently line ~174), e.g.:

```yaml
        prometheusSpec:
          enableAdminAPI: true
          enableFeatures:
            - memory-snapshot-on-shutdown
          enableOTLPReceiver: true
```

- [ ] **Step 2: Verify**

```bash
flux get kustomization kube-prometheus-stack
kubectl -n observability get pods -l app.kubernetes.io/name=prometheus
kubectl -n observability get statefulset prometheus-kube-prometheus-stack-prometheus -o jsonpath='{.spec.template.spec.containers[0].args}'
```

Expected: Prometheus pods restarted with `--web.enable-otlp-receiver` in args.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/observability/kube-prometheus-stack/app/helm-release.yaml
git commit -m "feat(kube-prometheus-stack): enable native otlp receiver"
```

---

## Task 7: loki — additive otlp_config

**Files:**
- Modify: `kubernetes/main/apps/observability/loki/app/helm-release.yaml`

**Interfaces:**
- Produces: Loki `/otlp/v1/logs` (already enabled by default) with OTLP resource-attribute → label mapping (consumed by the collector's `otlphttp/loki` exporter).

- [ ] **Step 1: Add `otlp_config` under `limits_config:`** — extend the existing `limits_config:` block (currently `retention_period: 30d` at ~line 37):

```yaml
      limits_config:
        retention_period: 30d
        otlp_config:
          resource_attributes:
            attributes_config:
              - action: index_label
                attributes:
                  - service.name
                  - k8s.namespace.name
                  - k8s.pod.name
                  - k8s.container.name
          ignore_defaults: true
```

- [ ] **Step 2: Verify**

```bash
flux get kustomization loki
kubectl -n observability get pods -l app.kubernetes.io/name=loki
kubectl -n observability exec deploy/loki -- wget -qO- http://localhost:3100/otlp/v1/logs 2>/dev/null || true
```

Expected: Loki pods restarted; `/otlp/v1/logs` endpoint present (additive — Promtail push path unaffected).

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/observability/loki/app/helm-release.yaml
git commit -m "feat(loki): add otlp log ingestion config"
```

---

## Task 8: grafana — add Tempo datasource

**Files:**
- Modify: `kubernetes/main/apps/observability/grafana/instance/datasource.yaml`

**Interfaces:**
- Consumes: `tempo` Service (Task 4) on query port 3200.

- [ ] **Step 1: Append a Tempo `GrafanaDatasource` document**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadatasource_v1beta1.json
# https://grafana.github.io/grafana-operator/docs/examples/datasource/
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: tempo
spec:
  instanceSelector:
    matchLabels:
      grafana.internal/instance: grafana
  datasource:
    type: tempo
    name: tempo
    access: proxy
    url: http://tempo.observability.svc.cluster.local:3200 #NOSONAR allow http
```

- [ ] **Step 2: Verify**

```bash
flux get kustomization grafana-instance
kubectl -n observability get grafanadatasource tempo
```

Expected: `tempo` GrafanaDatasource present; Tempo datasource queryable in Grafana → Explore.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/observability/grafana/instance/datasource.yaml
git commit -m "feat(grafana): add tempo datasource"
```

---

## Final End-to-End Verification

Run after all tasks, per the spec's "Post-Deployment Verification":

1. OTel Collector DaemonSet pods running on all nodes.
2. External OTLP reachable: `curl -H "Authorization: Bearer <token>" https://otel.techtales.io/v1/metrics`.
3. opencode metrics in Prometheus via native OTLP — query `service.name`-labelled series in Grafana Explore (intermittent across replicas is expected — scatter).
4. opencode traces in Tempo — verify Tempo datasource in Grafana Explore.
5. opencode logs in Loki — verify `/otlp/v1/logs` labels (`service.name`, etc.) in Grafana Explore.
6. Collector self-monitoring — `otel-collector` target up in Prometheus (port 8888).
7. Promtail still shipping logs (unchanged).
8. All existing ServiceMonitors still functional.



