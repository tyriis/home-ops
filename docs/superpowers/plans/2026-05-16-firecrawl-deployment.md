# Firecrawl Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Firecrawl v2.10 to the `ai` namespace with 6 controllers (api, worker, extract-worker, nuq-worker, nuq-prefetch-worker, playwright-service), backed by Dragonfly (Redis) and CNPG (PostgreSQL).

**Architecture:** Single bjw-s app-template HelmRelease with 6 controllers and 2 services. No Envoy Gateway HTTPRoute (internal-only). OpenBao for secrets. CNPG Database CR for NUQ queue storage.

**Tech Stack:** bjw-s/app-template v5.0.1, Flux HelmRelease, External Secrets Operator, CNPG/dbman

---

### Task 1: Create Flux sync and Kustomize scaffolding

**Files:**
- Create: `kubernetes/main/apps/ai/firecrawl/flux-sync.yaml`
- Create: `kubernetes/main/apps/ai/firecrawl/app/kustomization.yaml`

- [ ] **Step 1: Create flux-sync.yaml**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app firecrawl
  namespace: &namespace ai
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/ai/firecrawl/app
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
    - name: dragonfly-cluster
      namespace: dragonfly-system
    - name: cnpg-cluster
      namespace: cnpg-system
    - name: external-secrets-stores
      namespace: secops
  postBuild:
    substitute:
      APP: *app
      NAMESPACE: *namespace
```

- [ ] **Step 2: Create app/kustomization.yaml**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helm-release.yaml
  - ./external-secret.yaml
  - ./database.yaml
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/ai/firecrawl/
git commit -m "feat(firecrawl): add flux sync and kustomize scaffolding #8835"
```

---

### Task 2: Create ExternalSecret and CNPG Database

**Files:**
- Create: `kubernetes/main/apps/ai/firecrawl/app/external-secret.yaml`
- Create: `kubernetes/main/apps/ai/firecrawl/app/database.yaml`

- [ ] **Step 1: Create external-secret.yaml**

Two ExternalSecrets — one for DB init credentials, one for app runtime env:

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name firecrawl-db-init
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
        INIT_POSTGRES_USER: "{{ .NUQ_DB_USER }}"
        INIT_POSTGRES_PASS: "{{ .NUQ_DB_PASS }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/ai/firecrawl

---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name firecrawl-env
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
        BULL_AUTH_KEY: "{{ .BULL_AUTH_KEY }}"
        NUQ_DATABASE_URL: "postgresql://{{ .NUQ_DB_USER }}:{{ .NUQ_DB_PASS }}@postgres17-rw.cnpg-system.svc.cluster.local:5432/firecrawl_nuq"
        OPENAI_API_KEY: "{{ .OPENAI_API_KEY }}"
        SLACK_WEBHOOK_URL: "{{ .SLACK_WEBHOOK_URL }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/ai/firecrawl
```

- [ ] **Step 2: Create database.yaml**

```yaml
---
apiVersion: dbman.hef.sh/v1alpha3
kind: Database
metadata:
  name: firecrawl-nuq
spec:
  credentials:
    usernameSecretRef:
      name: firecrawl-db-init
      key: INIT_POSTGRES_USER
    passwordSecretRef:
      name: firecrawl-db-init
      key: INIT_POSTGRES_PASS
  databaseName: firecrawl_nuq
  databaseServerRef:
    name: postgres17
    namespace: cnpg-system
  prune: false
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/ai/firecrawl/app/external-secret.yaml kubernetes/main/apps/ai/firecrawl/app/database.yaml
git commit -m "feat(firecrawl): add external-secret and cnpg database cr"
```

---

### Task 3: Create the HelmRelease with 6 controllers

**Files:**
- Create: `kubernetes/main/apps/ai/firecrawl/app/helm-release.yaml`

- [ ] **Step 1: Create helm-release.yaml**

Six controllers in one HelmRelease using bjw-s/app-template:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app firecrawl
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

    controllers:
      api:
        replicas: 1
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/firecrawl
              tag: v2.10
            command: ["node", "--max-old-space-size=6144", "dist/src/index.js"]
            env:
              FLY_PROCESS_GROUP: app
              PORT: "3002"
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
              USE_DB_AUTHENTICATION: "false"
              ENV: production
              LOGGING_LEVEL: INFO
              IS_KUBERNETES: "true"
              HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: firecrawl-env
            ports:
              - name: http
                containerPort: 3002
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /v0/health/liveness
                    port: 3002
                  initialDelaySeconds: 30
                  periodSeconds: 30
                  timeoutSeconds: 5
                  failureThreshold: 3
              readiness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /v0/health/readiness
                    port: 3002
                  initialDelaySeconds: 30
                  periodSeconds: 30
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 2
                memory: 4Gi
              limits:
                cpu: 2
                memory: 6Gi

      worker:
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/firecrawl
              tag: v3.0.0
            command: ["node", "--max-old-space-size=3072", "dist/src/services/queue-worker.js"]
            env:
              FLY_PROCESS_GROUP: worker
              PORT: "3005"
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
              USE_DB_AUTHENTICATION: "false"
              ENV: production
              LOGGING_LEVEL: INFO
              IS_KUBERNETES: "true"
              HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: firecrawl-env
            ports:
              - name: http
                containerPort: 3005
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /liveness
                    port: 3005
                  initialDelaySeconds: 5
                  periodSeconds: 5
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 1
                memory: 3Gi
              limits:
                cpu: 1
                memory: 4Gi

      extract-worker:
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/firecrawl
              tag: v3.0.0
            command: ["node", "--max-old-space-size=2048", "dist/src/services/extract-worker.js"]
            env:
              FLY_PROCESS_GROUP: extract
              PORT: "3004"
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
              USE_DB_AUTHENTICATION: "false"
              ENV: production
              LOGGING_LEVEL: INFO
              IS_KUBERNETES: "true"
              HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: firecrawl-env
            ports:
              - name: http
                containerPort: 3004
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /liveness
                    port: 3004
                  initialDelaySeconds: 5
                  periodSeconds: 5
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 1
                memory: 2Gi
              limits:
                cpu: 1
                memory: 3Gi

      nuq-worker:
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/firecrawl
              tag: v3.0.0
            command: ["node", "--max-old-space-size=3072", "dist/src/services/nuq-worker.js"]
            env:
              FLY_PROCESS_GROUP: nuq
              PORT: "3006"
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
              USE_DB_AUTHENTICATION: "false"
              ENV: production
              LOGGING_LEVEL: INFO
              IS_KUBERNETES: "true"
              HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: firecrawl-env
            ports:
              - name: http
                containerPort: 3006
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /liveness
                    port: 3006
                  initialDelaySeconds: 5
                  periodSeconds: 5
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 1
                memory: 3Gi
              limits:
                cpu: 1
                memory: 4Gi

      nuq-prefetch-worker:
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/firecrawl
              tag: v3.0.0
            command: ["node", "--max-old-space-size=1024", "dist/src/services/nuq-prefetch-worker.js"]
            env:
              FLY_PROCESS_GROUP: prefetch
              PORT: "3011"
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
              USE_DB_AUTHENTICATION: "false"
              ENV: production
              LOGGING_LEVEL: INFO
              IS_KUBERNETES: "true"
              HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: firecrawl-env
            ports:
              - name: http
                containerPort: 3011
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /liveness
                    port: 3011
                  initialDelaySeconds: 5
                  periodSeconds: 5
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 500m
                memory: 1Gi
              limits:
                cpu: 1
                memory: 2Gi

      playwright-service:
        containers:
          app:
            image:
              repository: ghcr.io/firecrawl/playwright-service
              tag: latest
            env:
              PORT: "3000"
              BLOCK_MEDIA: "true"
              MAX_CONCURRENT_PAGES: "10"
            ports:
              - name: http
                containerPort: 3000
            probes:
              liveness:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: 3000
                  initialDelaySeconds: 30
                  periodSeconds: 30
                  timeoutSeconds: 5
                  failureThreshold: 3
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 1
                memory: 2Gi
              limits:
                cpu: 2
                memory: 4Gi

    service:
      api:
        controller: api
        ports:
          http:
            port: 3002
      playwright:
        controller: playwright-service
        ports:
          http:
            port: 3000

    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/ai/firecrawl/app/helm-release.yaml
git commit -m "feat(firecrawl): add helm-release with 6 controllers"
```

---

### Task 4: Register firecrawl in ai namespace kustomization

**Files:**
- Modify: `kubernetes/main/apps/ai/kustomization.yaml`

- [ ] **Step 1: Add firecrawl to kustomization.yaml**

Add `./firecrawl/flux-sync.yaml` to the resources list:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ai
components:
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./firecrawl/flux-sync.yaml
  - ./llm-guard/flux-sync.yaml
  - ./olla/flux-sync.yaml
  - ./ollama/flux-sync.yaml
  - ./open-webui/flux-sync.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/ai/kustomization.yaml
git commit -m "feat(firecrawl): register in ai namespace kustomization"
```
