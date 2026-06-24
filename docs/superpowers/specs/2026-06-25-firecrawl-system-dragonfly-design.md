# Firecrawl → `firecrawl-system` with dedicated Dragonfly — Design Doc

## Overview

Move firecrawl from the shared `ai` namespace into a new dedicated `firecrawl-system` namespace, and give it its own Dragonfly cluster via the existing `components/dragonfly` component. This follows the proven pattern from `feat(dragonfly): add own cluster for locking-service` (f66893e65) and `feat(dragonfly): implement immich cluster` (293650b8e).

The shared `dragonfly-system` cluster stays running — other consumers (atlantis, open-webui, oauth2-proxy) continue to use it.

## Motivation

- Per-app isolation: firecrawl's heavy queue/rate-limit traffic no longer competes with other apps on the shared cluster.
- Lifecycle ownership: firecrawl owns its cache lifecycle, scaling, and (eventual) backup policy.
- Operational consistency: matches the established per-app-DB pattern already in use for locking-service and immich.

## Target State

```
kubernetes/main/apps/
├── ai/                              (firecrawl entry removed)
│   ├── kustomization.yaml           (drop: - ./firecrawl/flux-sync.yaml)
│   ├── namespace.yaml
│   └── ...other ai apps (llm-guard, olla, ollama, open-webui)...
└── firecrawl-system/                (new)
    ├── kustomization.yaml
    ├── namespace.yaml
    └── firecrawl/                   (moved from ai/firecrawl/)
        ├── flux-sync.yaml
        └── app/
            ├── external-secret.yaml
            ├── helm-release.yaml
            └── kustomization.yaml
```

## Namespace

`firecrawl-system` — follows the `-system` suffix convention used by other infra-owned namespaces (anubis-system, argo-system, dragonfly-system, etc.).

- `namespace.yaml`: standard `Namespace` resource with `kustomize.toolkit.fluxcd.io/prune: disabled` label.
- `kustomization.yaml`: sets `namespace: firecrawl-system`, includes `components/flux/alerts`, references `namespace.yaml` and `firecrawl/flux-sync.yaml`.

## Dragonfly Cluster (via component)

Use the existing `components/dragonfly` component with default values. The component will create a `Dragonfly` CR named `firecrawl-dragonfly` in the `firecrawl-system` namespace with:

| Field | Value |
|-------|-------|
| Name | `firecrawl-dragonfly` |
| Image | `ghcr.io/dragonflydb/dragonfly:v1.39.0@<sha>` (inherited from component) |
| Replicas | 2 (default) |
| Memory limit | 512Mi |
| Args | `--maxmemory=…`, `--proactor_threads=2`, `--cluster_mode=emulated`, `--lock_on_hashtags`, `--default_lua_flags=allow-undeclared-keys` |

Service DNS: `firecrawl-dragonfly.firecrawl-system.svc.cluster.local:6379`.

The component also brings:

- A `PodMonitor` for `prometheus` scraping on the `admin` port (9999).
- A `NetworkPolicy` allowing ingress on port 9999 from `dragonfly-system/dragonfly-operator` (health checks) and `observability/prometheus` (metrics).
- A `RoleBinding` granting the operator write access to the per-app `Dragonfly` CR.

## `firecrawl/flux-sync.yaml` changes

```yaml
metadata:
  name: &app firecrawl
  namespace: &namespace firecrawl-system
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/dragonfly
  path: ./kubernetes/main/apps/firecrawl-system/firecrawl/app
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
    - name: dragonfly-crds
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

Notes:

- `dependsOn: dragonfly-cluster` → `dependsOn: dragonfly-crds`: the operator CRD must exist; the cluster itself is created by the component in the same Kustomization, so no order dependency is needed.
- `postBuild.substitute.NAMESPACE` added so the ExternalSecret/Component can target the new namespace consistently (future-proofing; only `APP` is currently consumed by the component).
- `postBuild.substitute.APP` is required by the component's `${APP}-dragonfly` naming.

## `app/helm-release.yaml` changes

### Redis URLs (3 controllers × 2 env vars = 6 lines)

Before:
```yaml
REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
```

After:
```yaml
REDIS_URL: redis://firecrawl-dragonfly.firecrawl-system.svc.cluster.local:6379
REDIS_RATE_LIMIT_URL: redis://firecrawl-dragonfly.firecrawl-system.svc.cluster.local:6379
```

### In-namespace service URLs

The `playwright-service` and `nuq-postgres` are part of the same `HelmRelease` and follow the Kustomization's `targetNamespace`. They move with the app. The `service` block wires them with names that match the controllers:

- `firecrawl-playwright` (controller `playwright-service`, port 3000)
- `firecrawl-nuq-postgres` (controller `nuq-postgres`, port 5432)

So `PLAYWRIGHT_MICROSERVICE_URL` and `NUQ_DATABASE_URL` in the `api` and `nuq-worker` controllers must change from `*.ai.svc.cluster.local` → `*.firecrawl-system.svc.cluster.local`:

Before:
```yaml
PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape #NOSONAR allow http
NUQ_DATABASE_URL: postgresql://postgres:password@firecrawl-nuq-postgres.ai.svc.cluster.local:5432/postgres
```

After:
```yaml
PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.firecrawl-system.svc.cluster.local:3000/scrape #NOSONAR allow http
NUQ_DATABASE_URL: postgresql://postgres:password@firecrawl-nuq-postgres.firecrawl-system.svc.cluster.local:5432/postgres
```

`PLAYWRIGHT_MICROSERVICE_URL` appears in `api`, `worker`, and `nuq-worker` (3 lines). `NUQ_DATABASE_URL` appears in `api` and `nuq-worker` (2 lines). Total: 5 lines.

## `app/external-secret.yaml` change

```yaml
dataFrom:
  - extract:
      key: infra/kubernetes/main/firecrawl-system/firecrawl #gitleaks:allow
```

The OpenBao path must be created manually as part of the rollout (out of band for this repo change).

## `ai/kustomization.yaml` change

Remove the single line:

```yaml
- ./firecrawl/flux-sync.yaml
```

The `ai` namespace, Flux alerts, and remaining apps (llm-guard, olla, ollama, open-webui) are unaffected.

## Out of Scope

- The shared `dragonfly-system` cluster remains untouched and continues to serve atlantis, open-webui, and oauth2-proxy.
- No new NetworkPolicies for firecrawl-system itself (intra-namespace access only; component's policy already covers metrics).
- No migration of cached data from the old cluster to the new one. firecrawl's redis usage is rate-limit + queue state — acceptable to start fresh on a clean cluster.
- No OIDC, gateway, or homepage changes.

## Rollout Notes

1. Commit the repo change.
2. Manually create the OpenBao secret at `infra/kubernetes/main/firecrawl-system/firecrawl` (copy from `infra/kubernetes/main/ai/firecrawl`).
3. Push — Flux reconciles. Firecrawl pods restart, connect to the new dragonfly cluster. The old shared cluster is no longer touched by firecrawl.
4. Verify by checking the firecrawl-api pod logs for `REDIS_URL` resolution and absence of rate-limit/queue errors.
