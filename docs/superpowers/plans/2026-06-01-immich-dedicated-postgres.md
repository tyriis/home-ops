# Immich Dedicated Postgres Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Immich's shared CNPG cluster binding (dbman Database resource) with a dedicated CNPG Cluster using `ghcr.io/immich-app/postgres` (PG18 + VectorChord + pgvector pre-installed), fixing the `permission denied` error on `CREATE EXTENSION vector`.

**Architecture:** A dedicated CNPG `Cluster` named `immich-db` is deployed in a new `database/` subfolder within the Immich app directory, targeting the `media` namespace. A new Flux Kustomization (`immich-database`) syncs this folder. The existing `immich` Kustomization gains a `dependsOn: immich-database` to ensure the cluster is ready before the HelmRelease starts. Immich app credentials are extended in-place (no new OpenBao paths). S3 backup credentials reuse the existing cnpg-system OpenBao path.

**Tech Stack:** Flux CD, CloudNativePG, barman-cloud plugin, bjw-s app-template v5, Kubernetes, YAML

---

## File Map

| Action | Path |
|--------|------|
| Modify | `kubernetes/main/apps/media/immich/flux-sync.yaml` |
| Create | `kubernetes/main/apps/media/immich/database/kustomization.yaml` |
| Create | `kubernetes/main/apps/media/immich/database/cluster.yaml` |
| Create | `kubernetes/main/apps/media/immich/database/objectstore.yaml` |
| Create | `kubernetes/main/apps/media/immich/database/scheduled-backup.yaml` |
| Create | `kubernetes/main/apps/media/immich/database/external-secret.yaml` |
| Modify | `kubernetes/main/apps/media/immich/app/external-secret.yaml` |
| Delete | `kubernetes/main/apps/media/immich/app/database.yaml` |
| Modify | `kubernetes/main/apps/media/immich/app/kustomization.yaml` |
| Modify | `kubernetes/main/apps/media/immich/app/configuration.yaml` |

---

### Task 1: Add `immich-database` Flux Kustomization and wire dependency

**Files:**
- Modify: `kubernetes/main/apps/media/immich/flux-sync.yaml`

- [ ] **Step 1: Add the `immich-database` Kustomization and add `dependsOn` to the existing `immich` Kustomization**

  Full file after change:

  ```yaml
  ---
  # yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: &app immich-database
  spec:
    targetNamespace: media
    commonMetadata:
      labels:
        app.kubernetes.io/name: *app
    path: ./kubernetes/main/apps/media/immich/database
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
      - name: cloudnative-pg
        namespace: cnpg-system
  ---
  # yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: &app immich
  spec:
    targetNamespace: media
    commonMetadata:
      labels:
        app.kubernetes.io/name: *app
    path: ./kubernetes/main/apps/media/immich/app
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
      - name: dragonfly-cluster
        namespace: dragonfly-system
      - name: immich-database
        namespace: flux-system
    postBuild:
      substitute:
        APP: *app
  ```

  > **Note:** Verify the correct name and namespace for the CNPG operator Kustomization by running:
  > ```bash
  > kubectl get kustomization -A | grep -i cnpg
  > ```
  > Replace `cloudnative-pg` / `cnpg-system` in the `dependsOn` above with whatever is returned.

---

### Task 2: Create the `database/` Kustomization index

**Files:**
- Create: `kubernetes/main/apps/media/immich/database/kustomization.yaml`

- [ ] **Step 1: Create `database/kustomization.yaml`**

  ```yaml
  ---
  # yaml-language-server: $schema=https://json.schemastore.org/kustomization
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - ./external-secret.yaml
    - ./cluster.yaml
    - ./objectstore.yaml
    - ./scheduled-backup.yaml
  ```

---

### Task 3: Create the S3 backup ExternalSecret

**Files:**
- Create: `kubernetes/main/apps/media/immich/database/external-secret.yaml`

The S3 credentials are reused from the existing OpenBao path `infra/kubernetes/main/cnpg-system/cluster` — no new OpenBao entries needed.

- [ ] **Step 1: Create `database/external-secret.yaml`**

  ```yaml
  ---
  # yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
  apiVersion: external-secrets.io/v1
  kind: ExternalSecret
  metadata:
    name: &name immich-s3
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
        metadata:
          labels:
            cnpg.io/reload: "true"
        data:
          AWS_ACCESS_KEY_ID: "{{ .AWS_ACCESS_KEY_ID }}"
          AWS_SECRET_ACCESS_KEY: "{{ .AWS_SECRET_ACCESS_KEY }}"
    dataFrom:
      - extract:
          key: infra/kubernetes/main/cnpg-system/cluster
  ```

---

### Task 4: Create the CNPG Cluster

**Files:**
- Create: `kubernetes/main/apps/media/immich/database/cluster.yaml`

The `bootstrap.initdb.secret` references `immich-db-init` — CNPG reads the `username` key from that secret to set the database owner (see Task 6 where these keys are added).

- [ ] **Step 1: Create `database/cluster.yaml`**

  ```yaml
  ---
  # yaml-language-server: $schema=https://schemas.tholinka.dev/postgresql.cnpg.io/cluster_v1.json
  apiVersion: postgresql.cnpg.io/v1
  kind: Cluster
  metadata:
    name: &name immich-db
    annotations:
      cnpg.io/skipEmptyWalArchiveCheck: "enabled"
  spec:
    instances: 1
    imageName: ghcr.io/immich-app/postgres:18-vectorchord0.5.3@sha256:8c10f8fd501a5dadbaf0b05acd1405ed20de93e69a1a01b3174e28428d7f3e12
    primaryUpdateMethod: switchover
    primaryUpdateStrategy: unsupervised
    storage:
      size: 20Gi
      storageClass: local-nvme
    enableSuperuserAccess: false
    bootstrap:
      initdb:
        database: immich
        secret:
          name: immich-db-init
    plugins:
      - name: barman-cloud.cloudnative-pg.io
        isWALArchiver: true
        parameters:
          barmanObjectName: *name
          serverName: *name
  ```

---

### Task 5: Create the ObjectStore and ScheduledBackup

**Files:**
- Create: `kubernetes/main/apps/media/immich/database/objectstore.yaml`
- Create: `kubernetes/main/apps/media/immich/database/scheduled-backup.yaml`

- [ ] **Step 1: Create `database/objectstore.yaml`**

  ```yaml
  ---
  # yaml-language-server: $schema=https://schemas.tholinka.dev/barmancloud.cnpg.io/objectstore_v1.json
  apiVersion: barmancloud.cnpg.io/v1
  kind: ObjectStore
  metadata:
    name: &name immich-db
  spec:
    retentionPolicy: 30d
    configuration:
      destinationPath: s3://cnpg/immich/
      endpointURL: https://s3.techtales.io
      s3Credentials:
        accessKeyId:
          name: immich-s3
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: immich-s3
          key: AWS_SECRET_ACCESS_KEY
  ```

- [ ] **Step 2: Create `database/scheduled-backup.yaml`**

  ```yaml
  ---
  # yaml-language-server: $schema=https://kube-schemas.pages.dev/postgresql.cnpg.io/scheduledbackup_v1.json
  apiVersion: postgresql.cnpg.io/v1
  kind: ScheduledBackup
  metadata:
    name: &name immich-db
  spec:
    schedule: "@daily"
    immediate: false
    backupOwnerReference: self
    cluster:
      name: *name
    method: plugin
    pluginConfiguration:
      name: barman-cloud.cloudnative-pg.io
  ```

---

### Task 6: Extend `immich-db-init` ExternalSecret with CNPG-compatible keys

**Files:**
- Modify: `kubernetes/main/apps/media/immich/app/external-secret.yaml`

CNPG's `bootstrap.initdb.secret` requires `username` and `password` keys. The `cnpg.io/reload: "true"` label tells CNPG to watch for secret rotations.

- [ ] **Step 1: Add `username`, `password` keys and the reload label to the existing ExternalSecret**

  Full file after change:

  ```yaml
  ---
  # yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
  apiVersion: external-secrets.io/v1
  kind: ExternalSecret
  metadata:
    name: &name immich-db-init
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
        metadata:
          labels:
            cnpg.io/reload: "true"
        data:
          INIT_POSTGRES_USER: "{{ .INIT_POSTGRES_USER }}"
          INIT_POSTGRES_PASS: "{{ .INIT_POSTGRES_PASS }}"
          INIT_POSTGRES_DB: immich
          username: "{{ .INIT_POSTGRES_USER }}"
          password: "{{ .INIT_POSTGRES_PASS }}"
    dataFrom:
      - extract:
          key: infra/kubernetes/main/media/immich
  ```

---

### Task 7: Remove the dbman Database resource

**Files:**
- Delete: `kubernetes/main/apps/media/immich/app/database.yaml`
- Modify: `kubernetes/main/apps/media/immich/app/kustomization.yaml`

- [ ] **Step 1: Delete `app/database.yaml`**

  ```bash
  rm kubernetes/main/apps/media/immich/app/database.yaml
  ```

- [ ] **Step 2: Remove the `database.yaml` reference from `app/kustomization.yaml`**

  Full file after change:

  ```yaml
  ---
  # yaml-language-server: $schema=https://json.schemastore.org/kustomization
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - ./external-secret.yaml
    - ./configuration.yaml
    - ./helm-release.yaml
  ```

---

### Task 8: Update `DB_HOSTNAME` to point to the dedicated CNPG cluster

**Files:**
- Modify: `kubernetes/main/apps/media/immich/app/configuration.yaml`

The CNPG Cluster named `immich-db` in the `media` namespace exposes a read-write service at `immich-db-rw`.

- [ ] **Step 1: Update `DB_HOSTNAME`**

  Full file after change:

  ```yaml
  ---
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: immich-config
  data:
    DB_HOSTNAME: immich-db-rw
    REDIS_HOSTNAME: dragonfly.dragonfly-system.svc.cluster.local
    IMMICH_MEDIA_LOCATION: /media
    IMMICH_MACHINE_LEARNING_ENABLED: "false"
    IMMICH_SERVER_URL: https://immich.techtales.io
  ```

---

### Task 9: Stage all changes for review

- [ ] **Step 1: Stage all changes**

  ```bash
  git add \
    kubernetes/main/apps/media/immich/flux-sync.yaml \
    kubernetes/main/apps/media/immich/database/ \
    kubernetes/main/apps/media/immich/app/external-secret.yaml \
    kubernetes/main/apps/media/immich/app/kustomization.yaml \
    kubernetes/main/apps/media/immich/app/configuration.yaml
  git rm kubernetes/main/apps/media/immich/app/database.yaml
  git status
  ```

- [ ] **Step 2: Present staged diff to user for CHECKPOINT 3 approval before any commit or push**
