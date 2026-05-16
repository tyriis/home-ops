# Firecrawl Deployment Design

## Overview

Deploy Firecrawl (web scraping API) to the main cluster's `ai/` namespace using individual bjw-s app-template controllers within a single HelmRelease. No Gateway API HTTPRoute — internal-only via Kubernetes Service DNS.

## Architecture

```
                  ┌──────────────┐
                  │  Dragonfly   │
                  │  (Redis)     │
                  └──────┬───────┘
                         │ redis://dragonfly.dragonfly-system.svc:6379
                         │
     ┌───────────────────┼───────────────────┐
     │                   │                   │
┌────▼────────┐  ┌──────▼──────┐  ┌─────────▼────────┐
│   api:3002  │  │   worker    │  │ extract-worker   │
│ (main API)  │  │  :3005      │  │   :3004          │
└────┬────────┘  └──────┬──────┘  └─────────┬────────┘
     │                  │                   │
     │           ┌──────▼────────┐  ┌───────▼─────────┐
     │           │  nuq-worker   │  │ nuq-prefetch    │
     │           │  :3006        │  │ -worker:3011    │
     │           └──────────────-┘  └─────────────────┘
     │
     │  http://firecrawl-playwright.ai.svc:3000/scrape
     │
┌────▼────────────────┐
│ playwright-service  │
│  :3000              │
│  POST /scrape       │
│  GET /health        │
└─────────────────────┘
                         ┌──────────────┐
                         │  CNPG        │
                         │  (PostgreSQL)│
                         │  postgres17  │
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │  firecrawl   │
                         │  _nuq DB     │
                         └──────────────┘
```

## Directory Structure

```
kubernetes/main/apps/ai/
├── kustomization.yaml
├── namespace.yaml
├── firecrawl/
│   ├── flux-sync.yaml
│   └── app/
│       ├── kustomization.yaml
│       ├── helm-release.yaml
│       ├── external-secret.yaml
│       └── database.yaml
```

## Flux Sync

`firecrawl/flux-sync.yaml` — standard Flux Kustomization pointing at `./kubernetes/main/apps/ai/firecrawl/app`. Depends on `dragonfly-cluster` (for Redis) and `cnpg` (for PostgreSQL).

## HelmRelease Controllers

Single HelmRelease named `firecrawl` using `bjw-s/app-template` chart (v5.0.1).

### Controllers

All Firecrawl components use `ghcr.io/firecrawl/firecrawl` image except playwright-service which uses `ghcr.io/firecrawl/playwright-service`. Image tags pinned to v2.10.

| Controller | Image | Command | Port | Replicas |
|---|---|---|---|---|
| api | firecrawl | `node --max-old-space-size=6144 dist/src/index.js` | 3002 | 1 |
| worker | firecrawl | `node --max-old-space-size=3072 dist/src/services/queue-worker.js` | 3005 | 1 |
| extract-worker | firecrawl | `node --max-old-space-size=2048 dist/src/services/extract-worker.js` | 3004 | 1 |
| nuq-worker | firecrawl | `node --max-old-space-size=3072 dist/src/services/nuq-worker.js` | 3006 | 1 |
| nuq-prefetch-worker | firecrawl | `node --max-old-space-size=1024 dist/src/services/nuq-prefetch-worker.js` | 3011 | 1 |
| playwright-service | playwright-service | (default entrypoint) | 3000 | 1 |

### Services

Only services that receive network connections:

| Service Name | Controller | Port | DNS |
|---|---|---|---|
| api | api | 3002 | `firecrawl-api.ai.svc.cluster.local` |
| playwright | playwright-service | 3000 | `firecrawl-playwright.ai.svc.cluster.local` |

Workers (worker, extract-worker, nuq-worker, nuq-prefetch-worker) do not need Services.

### Probes

| Controller | Type | Path | Port |
|---|---|---|---|
| api | readiness | `/v0/health/readiness` | 3002 |
| api | liveness | `/v0/health/liveness` | 3002 |
| worker | liveness | `/liveness` | 3005 |
| extract-worker | liveness | `/liveness` | 3004 |
| nuq-worker | liveness | `/liveness` | 3006 |
| nuq-prefetch-worker | liveness | `/liveness` | 3011 |
| playwright-service | liveness | `/health` | 3000 |

### Resource Requests/Limits

| Controller | CPU req | RAM req | CPU limit | RAM limit |
|---|---|---|---|---|
| api | 2 | 4Gi | 2 | 6Gi |
| worker | 1 | 3Gi | 1 | 4Gi |
| extract-worker | 1 | 2Gi | 1 | 3Gi |
| nuq-worker | 1 | 3Gi | 1 | 4Gi |
| nuq-prefetch-worker | 0.5 | 1Gi | 1 | 2Gi |
| playwright-service | 1 | 2Gi | 2 | 4Gi |

### Environment Variables

#### Shared (all Firecrawl controllers except playwright-service)

```yaml
REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape
NUQ_DATABASE_URL: postgresql://$(NUQ_DB_USER):$(NUQ_DB_PASS)@postgres17-rw.cnpg-system.svc.cluster.local:5432/firecrawl_nuq
USE_DB_AUTHENTICATION: "false"
ENV: production
LOGGING_LEVEL: INFO
IS_KUBERNETES: "true"
HOST: 0.0.0.0
```

#### Per-controller

```yaml
api:       { FLY_PROCESS_GROUP: app, PORT: "3002" }
worker:    { FLY_PROCESS_GROUP: worker, PORT: "3005" }
extract-worker: { FLY_PROCESS_GROUP: extract, PORT: "3004" }
nuq-worker:    { FLY_PROCESS_GROUP: nuq, PORT: "3006" }
nuq-prefetch-worker: { FLY_PROCESS_GROUP: prefetch, PORT: "3011" }
```

#### Playwright-service

```yaml
PORT: "3000"
BLOCK_MEDIA: "true"
MAX_CONCURRENT_PAGES: "10"
```

## Secrets

ExternalSecret from OpenBao at path `infra/kubernetes/main/ai/firecrawl`:

| Secret Key | Purpose |
|---|---|
| `BULL_AUTH_KEY` | Queue admin UI authentication |
| `OPENAI_API_KEY` | AI features (optional) |
| `SLACK_WEBHOOK_URL` | Health alerts (optional) |
| `NUQ_DB_USER` | CNPG database user |
| `NUQ_DB_PASS` | CNPG database password |

ExternalSecret creates `firecrawl-env` secret consumed via `envFrom` by all Firecrawl controllers.

## Database

CNPG Database CR (`database.yaml`):

```yaml
apiVersion: dbman.hef.sh/v1alpha3
kind: Database
metadata:
  name: firecrawl-nuq
spec:
  databaseName: firecrawl_nuq
  credentials:
    usernameSecretRef:
      name: firecrawl-db-init
      key: INIT_POSTGRES_USER
    passwordSecretRef:
      name: firecrawl-db-init
      key: INIT_POSTGRES_PASS
  databaseServerRef:
    name: postgres17
    namespace: cnpg-system
  prune: false
```

Separate ExternalSecret `firecrawl-db-init` creates the init credentials from OpenBao.

## Gateway API (Envoy Gateway)

No HTTPRoute is defined for Firecrawl — it is not exposed via Envoy Gateway. All access is internal-only via standard Kubernetes Service DNS:

- API: `http://firecrawl-api.ai.svc.cluster.local:3002`
- Playwright: `http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape`

## Dependencies

firecrawl depends on `dragonfly-cluster` (for Redis) and `cnpg` (for CNPG cluster). These are declared via `dependsOn` in the flux-sync.yaml.

## Playwright Service

Firecrawl's custom Express.js wrapper around Playwright (not the upstream MS Playwright Docker image). Exposes `POST /scrape` and `GET /health`. Deployed as a controller in the same HelmRelease.

## Security

- `global.createDefaultServiceAccount: false`
- Containers run as non-root
- Read-only root filesystem
- Drop all capabilities
- No Gateway API HTTPRoute (internal only)
