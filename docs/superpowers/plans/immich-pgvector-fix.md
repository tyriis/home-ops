# Immich pgvector Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the `permission denied to create extension "vector"` error in Immich by deploying a dedicated Postgres controller using the `ghcr.io/immich-app/postgres` image within the Immich `HelmRelease`.

**Architecture:** We are moving Immich's database off the shared CloudNativePG cluster. Instead, we are adding a local `postgres` controller to Immich's app-template `HelmRelease`. This bypasses the extension creation issue because the `ghcr.io/immich-app/postgres` image comes with `pgvector` built-in and enabled.

**Tech Stack:** Kubernetes, Flux, bjw-s app-template, PostgreSQL.

---

### Task 1: Delete Shared Database Binding

**Files:**
- Delete: `kubernetes/main/apps/media/immich/app/database.yaml`

- [ ] **Step 1: Delete the file**
```bash
rm kubernetes/main/apps/media/immich/app/database.yaml
```

- [ ] **Step 2: Commit**
```bash
git add kubernetes/main/apps/media/immich/app/database.yaml
git commit -m "refactor: remove dbman binding for immich #8852"
```

### Task 2: Update Immich HelmRelease with Postgres Controller

**Files:**
- Modify: `kubernetes/main/apps/media/immich/app/helm-release.yaml`

- [ ] **Step 1: Add Postgres Controller and update DB_HOSTNAME**
Open `kubernetes/main/apps/media/immich/app/helm-release.yaml`.
Update the `env` section under `server` controller to set `DB_HOSTNAME`.
Add a new `postgres` controller alongside `server`.

```yaml
# Under controllers.server.containers.app.env add:
              DB_HOSTNAME: immich-postgres.media.svc.cluster.local
```

```yaml
# Under controllers add:
      postgres:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: ghcr.io/immich-app/postgres
              tag: 16-vectorchord0.4.3-pgvector0.8.0-pgvectors0.3.0
            env:
              POSTGRES_DB:
                valueFrom:
                  secretKeyRef:
                    name: immich-db-init
                    key: INIT_POSTGRES_DB
              POSTGRES_USER:
                valueFrom:
                  secretKeyRef:
                    name: immich-db-init
                    key: INIT_POSTGRES_USER
              POSTGRES_PASSWORD:
                valueFrom:
                  secretKeyRef:
                    name: immich-db-init
                    key: INIT_POSTGRES_PASS
            securityContext:
              runAsUser: 999
              runAsGroup: 999
              runAsNonRoot: true
            resources:
              requests:
                cpu: 100m
                memory: 512Mi
              limits:
                memory: 1Gi
```

- [ ] **Step 2: Update Persistence and Service**
In the same file, add a `postgres` service under `service`:
```yaml
      postgres:
        controller: postgres
        ports:
          http:
            port: 5432
```
Add `postgres-data` persistence under `persistence`:
```yaml
      postgres-data:
        type: persistentVolumeClaim
        accessMode: ReadWriteOnce
        size: 50Gi
        storageClass: local-nvme # verify this is your intended class
        advancedMounts:
          postgres:
            app:
              - path: /var/lib/postgresql/data
```

- [ ] **Step 3: Commit**
```bash
git add kubernetes/main/apps/media/immich/app/helm-release.yaml
git commit -m "feat: add dedicated postgres controller with pgvector for immich #8852"
```
