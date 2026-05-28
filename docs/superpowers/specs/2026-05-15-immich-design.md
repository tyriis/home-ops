# Immich Deployment Design

**Date:** 2026-05-15
**Scope:** Phase 1 — Immich server (no ML) in devenv for local testing, then main cluster production deployment.
**Phase 2 (out of scope):** Machine learning microservice.

---

## Overview

Deploy Immich (self-hosted photo/video management) using the bjw-s `app-template` Helm chart.
The rollout is two-phased: validate in the local `devenv` kind cluster first, then promote to the `main` cluster.

---

## Phase 1: Devenv (local testing)

### Goal

Get Immich running locally in the devenv kind cluster with all dependencies self-contained,
so the configuration and app behaviour can be validated before touching the main cluster.

### File Structure

```
devenv/oci/apps/media/
├── namespace.yaml                    # media namespace (new)
├── kustomization.yaml                # namespace-level Kustomization (new)
└── immich/
    ├── flux-sync.yaml               # Flux Kustomization (uncomment + complete)
    └── app/
        ├── kustomization.yaml       # lists: helm-release, secret, configuration
        ├── helm-release.yaml        # app-template with server/postgres/dragonfly controllers
        ├── secret.yaml              # plain Secret (committed, trivial devenv credentials)
        └── configuration.yaml       # ConfigMap immich-config
```

### HelmRelease — app-template controllers

All three controllers live in a single HelmRelease using `bjw-s/app-template` (match version used
by other devenv apps — verify at implementation time).

| Controller  | Image                                                | Notes                                       |
| ----------- | ---------------------------------------------------- | ------------------------------------------- |
| `server`    | `ghcr.io/immich-app/immich-server:<latest>`          | Immich API + web UI, port 2283              |
| `postgres`  | `ghcr.io/immich-app/postgres:17-vectorchord<latest>` | Postgres 17 with vectorchord extension      |
| `dragonfly` | `docker.io/dragonflydb/dragonfly:<latest>`           | Redis-compatible, port 6379, no persistence |

Renovate will manage image tag updates once pinned.

### Persistence

| PVC               | Storage class | Mount                                 | Purpose       |
| ----------------- | ------------- | ------------------------------------- | ------------- |
| `immich-library`  | local-path    | `/media` (server)                     | Media library |
| `immich-postgres` | local-path    | `/var/lib/postgresql/data` (postgres) | DB data       |

### Secrets (`secret.yaml`)

Plain `Secret` manifest committed to git. Acceptable because devenv uses trivial credentials
and is a local-only kind cluster.

```
immich-secret:
  DB_USERNAME: immich
  DB_PASSWORD: immich
  DB_DATABASE_NAME: immich
```

### Configuration (`configuration.yaml`)

ConfigMap `immich-config` with key env vars:

| Var                               | Devenv value                                        |
| --------------------------------- | --------------------------------------------------- |
| `DB_HOSTNAME`                     | `immich-postgres` (service name in same namespace)  |
| `DB_DATABASE_NAME`                | `immich`                                            |
| `REDIS_HOSTNAME`                  | `immich-dragonfly` (service name in same namespace) |
| `IMMICH_MEDIA_LOCATION`           | `/media`                                            |
| `IMMICH_MACHINE_LEARNING_ENABLED` | `false`                                             |

`DB_USERNAME` and `DB_PASSWORD` come from `immich-secret`, not this ConfigMap.

### Ingress

HTTPRoute via Envoy Gateway at `immich.local`.

### Flux Kustomization dependencies

The `flux-sync.yaml` should depend on:

- `cert-manager` (networking/TLS)
- `envoy-gateway` (HTTPRoute)

### What devenv does NOT have

- No ExternalSecret / OpenBao (plain Secret used instead)
- No dbman Database CRD (postgres runs inline as a controller)
- No VolSync
- No ML controller

---

## Phase 2: Main Cluster

### Goal

Production-grade Immich deployment in `kubernetes/main/apps/media/`, following all existing
media app conventions. No ML.

### File Structure

```
kubernetes/main/apps/media/
├── kustomization.yaml               # MODIFY: add immich/flux-sync.yaml
└── immich/
    ├── flux-sync.yaml               # Flux Kustomization with full dependency chain
    └── app/
        ├── kustomization.yaml       # lists all resources
        ├── helm-release.yaml        # app-template v5.0.1, server controller only
        ├── oci-repository.yaml      # bjw-s app-template OCI source
        ├── configuration.yaml       # ConfigMap immich-config
        ├── external-secret.yaml     # OpenBao → immich-secret
        └── database.yaml            # dbman Database CRD → postgres17
```

### HelmRelease — app-template controllers

Single `server` controller. ML is explicitly disabled via env var.

| Controller | Image                                       | Notes                   |
| ---------- | ------------------------------------------- | ----------------------- |
| `server`   | `ghcr.io/immich-app/immich-server:<latest>` | API + web UI, port 2283 |

### Persistence

NFS mount from NAS:

| Mount    | NFS path                           | Purpose              |
| -------- | ---------------------------------- | -------------------- |
| `/media` | `nas.techtales.io:/mnt/tank/media` | Media library on NAS |

No VolSync needed:

- Media lives on NAS (backed up at NAS level)
- Config is fully managed via IaC
- Database is managed by CNPG (handles its own backups via barman)

### Secrets — ExternalSecret

OpenBao `ClusterSecretStore` named `openbao-backend`.
Key path: `infra/kubernetes/main/media/immich`

Fields to provision in OpenBao before deployment:

| Field         | Description                  |
| ------------- | ---------------------------- |
| `DB_USERNAME` | Postgres username for Immich |
| `DB_PASSWORD` | Postgres password for Immich |

Rendered into `immich-secret` Kubernetes Secret.

### Database — dbman CRD

`database.yaml` creates an `immich` database on the existing `postgres17` CNPG cluster
in `cnpg-system`, using credentials from `immich-secret`.

```yaml
spec:
  databaseName: immich
  databaseServerRef:
    name: postgres17
    namespace: cnpg-system
  prune: false
```

Note: the postgres17 image used by the CNPG cluster must include the vectorchord/pgvecto.rs
extension. Verify at implementation time that the existing postgres17 server supports this.

### Redis — shared Dragonfly

Existing shared Dragonfly instance:
`dragonfly.dragonfly-system.svc.cluster.local:6379`

No dedicated Dragonfly deployment needed for Immich.

### Configuration (`configuration.yaml`)

ConfigMap `immich-config`:

| Var                               | Main cluster value                                                      |
| --------------------------------- | ----------------------------------------------------------------------- |
| `DB_HOSTNAME`                     | `postgres17-rw.cnpg-system.svc.cluster.local` (CNPG read-write service) |
| `REDIS_HOSTNAME`                  | `dragonfly.dragonfly-system.svc.cluster.local`                          |
| `IMMICH_MEDIA_LOCATION`           | `/media`                                                                |
| `IMMICH_MACHINE_LEARNING_ENABLED` | `false`                                                                 |
| `IMMICH_SERVER_URL`               | `https://immich.techtales.io`                                           |

### Ingress

HTTPRoute via Envoy Gateway at `immich.techtales.io`.
Follows the same pattern as other media apps (see `filebrowser` or `jellyfin`).

### Flux Kustomization dependencies (`flux-sync.yaml`)

```yaml
dependsOn:
  - name: external-secrets-stores
    namespace: secops
  - name: dbman
    namespace: cnpg-system
  - name: dragonfly-operator # verify exact name at implementation time
    namespace: dragonfly-system
```

---

## Deferred: Phase 3 — Machine Learning

ML will be added as a follow-up in a separate implementation cycle. The `server` controller's
`IMMICH_MACHINE_LEARNING_ENABLED=false` env var ensures no ML calls are attempted.

When ML is added, a second `machine-learning` controller will be added to the HelmRelease
with its own resource limits, and the env var will be removed or set to `true`.

---

## Implementation Order

1. Complete and activate devenv Immich — validate locally
2. Provision OpenBao secret at `infra/kubernetes/main/media/immich`
3. Verify postgres17 CNPG cluster has vectorchord extension
4. Deploy main cluster Immich
5. Register an admin user and verify photo upload + browsing works

---

## Open Questions / Verify at Implementation Time

- Exact `ghcr.io/immich-app/postgres:17-vectorchord<X>` tag to pin
- Exact app-template version used in devenv (align with existing devenv apps)
- Confirm dragonfly Flux Kustomization name and namespace in main cluster
- Confirm DB hostname produced by dbman for the `immich` database
- Confirm postgres17 CNPG cluster has vectorchord/pgvecto.rs extension installed
