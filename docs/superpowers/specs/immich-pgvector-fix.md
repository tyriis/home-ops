# Immich pgvector Fix Spec

**Ticket:** #8852

**Goal:** Resolve the `permission denied to create extension "vector"` error in Immich deployment.

**Architecture:**
Immich version 2.7.5 uses PostgreSQL with the `pgvector` extension.
Our existing deployment provisions the database via `dbman.hef.sh/v1alpha3` into a shared CloudNativePG cluster.
Because Immich connects as an unprivileged user, it cannot automatically create C-based extensions like `pgvector`.
Instead of manually injecting the extension into the shared cluster, we will deploy a dedicated PostgreSQL instance.
We will deploy this within the Immich `HelmRelease`.
We will use the `ghcr.io/immich-app/postgres:16-vectorchord0.4.3-pgvector0.8.0-pgvectors0.3.0` image.
This isolates Immich's database workloads natively includes the required `pgvector` extension.

**Changes required:**
1. Delete the `database.yaml` file that binds Immich to the shared CNPG cluster.
2. Update the `immich` `HelmRelease` (`kubernetes/main/apps/media/immich/app/helm-release.yaml`).
   Add a new `postgres` controller using the `ghcr.io/immich-app/postgres` image.
3. Configure the `postgres` controller with necessary environment variables.
   Use `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` matching credentials from `immich-db-init` secret.
4. Add persistence for the new Postgres controller so data survives restarts.
5. Update Immich's `DB_HOSTNAME` environment variable to point to the new local Postgres service.

**Tech Stack:** Kubernetes, Flux, bjw-s app-template, PostgreSQL.
