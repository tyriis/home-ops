# Forgejo on the utility cluster — implementation spec

Date: 2026-09-14
Ticket: #10489
ADR: docs/decisions/0014-host-forgejo-on-the-single-node-utility-cluster.md

Design for deploying Forgejo on the utility cluster. Follows existing repo conventions verbatim —
every pattern here is copied from a working example in this repo (paths cited). Scope is manifests
only (GitOps-first); bucket/key creation and OpenBao writes are manual steps on external systems.

## 1. Layout and naming

New namespace on **utility**: `forgejo-system` (`kubernetes/utility/apps/forgejo-system/`).
New namespace on **main**: `forgejo-runners` (`kubernetes/main/apps/forgejo-runners/`).
CNPG components join the **existing** `cnpg-system` pattern → new folder
`kubernetes/utility/apps/cnpg-system/` (utility has no cnpg-system today).

| Resource | Name | Namespace |
| --- | --- | --- |
| CNPG Cluster + ObjectStore + ScheduledBackup | `forgejo-db` | cnpg-system (utility) |
| Forgejo HelmRelease + PVC | `forgejo` | forgejo-system |
| VolSync ReplicationSource (data PVC) | `forgejo-data` | forgejo-system |
| Dump CronJob | `forgejo-dump` | forgejo-system |
| act_runner Deployment + registration Secret | `act-runner` | forgejo-runners (main) |
| PocketID client / OIDC secret | `forgejo` / `forgejo-oidc` | forgejo-system |

Hostname: `git.utility.techtales.io` (utility-gateway hosts: `*.techtales.io` and
`*.utility.techtales.io` are already on the utility envoy Gateway). SSH: ClusterIP + **Envoy
Gateway TCPRoute** (no LoadBalancer IP needed; bjw-s pattern).

## 2. Sync wiring (utility)

Copy the echo-server chain exactly:

- `forgejo-system/{namespace.yaml,kustomization.yaml}` — namespace with
  `kustomize.toolkit.fluxcd.io/prune: disabled` annotation; kustomization lists `./namespace.yaml`
  and app `flux-sync.yaml`s; components: `../../../components/flux/alerts`.
- Per app: `flux-sync.yaml` (Flux Kustomization, `path: .../app`, `postBuild.substitute.APP`,
  sensible `dependsOn`) + `app/kustomization.yaml` + `app/helm-release.yaml`.
- `cnpg-system/` on utility mirrors the main-cluster chain: `cnpg/flux-sync.yaml` with separate
  Kustomizations `cnpg-operator`, `cnpg-crds`, `cnpg-barman-cloud-crds`, `cnpg-barman-cloud`,
  `cnpg-cluster` (forgejo-db only); barman plugin pinned to the **same versions as main**: operator
  chart `0.29.0`, plugin `v0.15.0` via GitRepository CRD extraction. `cnpg-barman-cloud`
  dependsOn `cert-manager-issuers` (cert-manager exists on utility already).
- DB-man (dbman) is **omitted** on utility — main-only nicety, no dependency on it.

## 3. Storage

No new provisioner. Use existing democratic-csi StorageClass **`local-nvme`** (default SC on
utility, base path `/var/mnt/extra`, VolumeSnapshotClass `local-nvme` exists).

Manual prerequisite (human): confirm `/var/mnt/extra` on the utility node is backed by the 500GB
Samsung 870 EVO (talos install-disk selector targets the same disk family — must be verified, not
assumed). If it is the wrong disk, re-point the mount in talhelper and let Flux reconcile — this
spec assumes it is correct.

PVCs (all `local-nvme`, RWO):

| PVC | Size | Owner |
| --- | --- | --- |
| `forgejo-data` | 50Gi (SC has `allowVolumeExpansion: false` — size generously) | created via VolSync pvc.yaml pattern (below) |
| CNPG-managed PVC for `forgejo-db` | 20Gi | Cluster CR |

## 4. CNPG + barman-cloud (database)

Port of the proven main pattern (`kubernetes/main/apps/cnpg-system/...` and
`kubernetes/main/apps/media/immich/database/`), single-instance variant:

- `cluster.yaml`: Cluster `forgejo-db`, `instances: 1`, imageName pg 17.x (same as main),
  `storage: 20Gi / local-nvme`, `superuserSecret: forgejo-db-superuser`,
  `plugins: barman-cloud.cloudnative-pg.io (isWALArchiver, barmanObjectName/serverName: forgejo-db)`,
  annotation `cnpg.io/skipEmptyWalArchiveCheck: enabled`.
- `objectstore.yaml`: ObjectStore `forgejo-db`, destinationPath `s3://cnpg/utility/forgejo/`,
  endpointURL `https://s3.techtales.io`, credentials secret `forgejo-db-s3`.
- `scheduled-backup.yaml`: `@daily`, `method: plugin`, pluginConfiguration barman-cloud — verbatim
  shape of main's `scheduled-backup.yaml`.
- `external-secret.yaml`: utility ClusterSecretStore `openbao-backend`, key
  `infra/kubernetes/utility/cnpg-system/forgejo-db-s3`.

App connectivity: Forgejo uses the direct service `forgejo-db-rw.cnpg-system.svc:5432` (no pooler —
1 replica, 2 users). DB role bootstrap uses the **init-db postRenderer** swap to
`ghcr.io/home-operations/postgres-init` (drag0n141 pattern) with an app Secret
`forgejo-db-app` (USER/PASSWORD/DATABASE/URI) sourced from ExternalSecret
`infra/kubernetes/utility/forgejo-system/forgejo/db`.

## 5. Forgejo app

Chart: official **forgejo-helm** (`code.forgejo.org/forgejo-helm/forgejo`, HelmRepository source —
no OCIRepository for this app). Values grounded in the kubesearch survey (bjw-s, drag0n141,
joryirving), single-replica/CNPG shape:

- image rootless; bundled `postgresql[-ha]`, `redis-cluster`, `memcached` all disabled.
- `persistence.enabled: true, create: false, claimName: forgejo-data` at `/data` — PVC lifecycle
  owned outside the chart.
- **No cache/queue/session block** (joryirving precedent — only config confirmed to run without a
  redis-protocol host at 1 replica; matches ADR decision).
- database: `DB_TYPE: postgres`, HOST/NAME/USER/PASSWD via `valuesFrom` targetPaths from
  `forgejo-db-app`; `SSL_MODE: disable`.
- Registration locked: `DISABLE_REGISTRATION`, `SHOW_REGISTRATION_BUTTON: false`,
  `ALLOW_ONLY_EXTERNAL_REGISTRATION: true`, `ENABLE_INTERNAL_SIGNIN: false`,
  `ENABLE_PASSWORD_SIGNIN_FORM: false`.
- Mail: `mailer.ENABLED: false`, `ENABLE_NOTIFY_MAIL: false`.
- OIDC: `gitea.oauth[]` provider `openidConnect`, `autoDiscoverUrl` → PocketID issuer
  (`https://id.techtales.io`), client id/secret via `existingSecret: forgejo-oidc`;
  `openid.ENABLE_OPENID_SIGNIN/SIGNUP: false`.
- Webhooks enabled (Discord org webhook is runtime config, not chart).
- Indexers: `REPO_INDEXER_ENABLED: true`, `ISSUE_INDEXER_TYPE: bleve` (no external search infra).
- HTTP surface: chart `httpRoute` disabled or pointed at the envoy Gateway
  (`parentRefs: envoy/networking/https`) with `external-dns/unifi: "true"` annotation — match
  utility echo-server route convention.
- SSH: chart `service.ssh.type: ClusterIP` + **TCPRoute** resource (Gateway API) with
  external-dns record `git.utility.techtales.io`. Note: the utility envoy Gateway only has
  `http`/`https` listeners — a TCP listener section must be added to
  `kubernetes/utility/apps/networking/envoy-gateway/config/gateway.yaml` (flagged in plan).
- SecurityPolicy (envoy-pocketid component): **not applied day 1** — an envoy-level OAuth guard
  breaks git-over-HTTPS (git clients cannot do OIDC redirects). Web-login protection is
  Forgejo-side: OIDC-only sign-in + `REQUIRE_SIGNIN_VIEW: true`.
- Admin bootstrap: `gitea.admin.existingSecret: forgejo-admin-secret` (username/password from
  OpenBao ExternalSecret), `passwordMode: initialOnlyRequireReset` (joryirving).

## 6. Backups

Target: S3 (MinIO at `s3.techtales.io`) backed by the **Aostar NAS**; DS218 holds offsite copies of
the buckets. Three legs + offsite per ADR:

1. **DB PITR** — barman-cloud WAL + `@daily` fulls (section 4).
2. **`/data` restic** — VolSync. Reuse `kubernetes/components/volsync/` component with per-app
   flux-sync `postBuild.substitute`: `VOLSYNC_STORAGECLASS=local-nvme`,
   `VOLSYNC_SNAPSHOTCLASS=local-nvme`, `VOLSYNC_CACHE_SNAPSHOTCLASS=local-nvme`,
   `VOLSYNC_CAPACITY=50Gi`, `VOLSYNC_PUID/PGID=1001` (forgejo rootless uid). The component's
   ExternalSecret hardcodes key path `infra/kubernetes/main/volsync/${APP}-...` — override with a
   patch in the app folder pointing at `infra/kubernetes/utility/volsync/forgejo-data`.
   `pvc.yaml` doubles as the PVC (VolSync bootstrap pattern). Trigger schedule: `*/15 * * * *`
   (ADR RPO ≤15 min).
3. **Nightly dump** — CronJob (plain k8s CronJob with kube-tools image + `forgejo dump` via
   ServiceAccount with pods/exec RBAC, or app-template cron mode). Runs
   `forgejo dump` → restic or `mc` mirror into `s3://forgejo-dump/` with `forgejo-dump-s3` creds.
4. **Manual**: DS218 offsite copy of the S3 buckets (existing offsite mechanism, out of
   repo scope — documented prerequisite).

Secrets: `forgejo-data-volsync-minio` (RESTIC_REPOSITORY/PASSWORD + AWS keys, key
`infra/kubernetes/utility/volsync/forgejo-data`).

## 7. act_runner on main

New namespace `forgejo-runners` (plain, no SOPS). Deployment (app-template 5.1.0) running
`code.forgejo.org/forgejo/runner` (tag-pinned) with `docker-daemon` sidecar (docker-in-docker
runner class), config from Secret: forge URL `https://git.utility.techtales.io`, registration token
ExternalSecret `infra/kubernetes/main/forgejo-runners/act-runner` (`RUNNER_TOKEN`).
Resource requests/limits set (runner = untrusted-exec territory): requests 100m/256Mi, limits
2 CPU/2Gi, own namespace, default NetworkPolicy posture per components.
Pull-based: no inbound connectivity from utility → main required.

## 8. Observability

Gatus lives on **main** only. Add a **static endpoint** to
`kubernetes/main/apps/observability/gatus/app/resources/config.yaml`:
`https://git.utility.techtales.io/api/healthz` (cross-cluster precedent:
`flux-webhook-utility` + dns-resolver entries exist).

## 9. Secrets inventory (OpenBao, manual provisioning)

| Key | Consumed by | Fields |
| --- | --- | --- |
| `infra/kubernetes/utility/cnpg-system/forgejo-db-s3` | ObjectStore | AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY |
| `infra/kubernetes/utility/forgejo-system/forgejo/db` | postgres-init + valuesFrom | username, password, database |
| `infra/kubernetes/utility/forgejo-system/forgejo/admin` | admin secret | username, password |
| `infra/kubernetes/utility/forgejo-system/forgejo/oidc` | existingSecret | client_id, client_secret |
| `infra/kubernetes/utility/volsync/forgejo-data` | VolSync repo | RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS_* |
| `infra/kubernetes/main/forgejo-runners/act-runner` | act_runner | RUNNER_TOKEN |

## 10. Manual / external prerequisites (NOT repo work)

1. Confirm `/var/mnt/extra` = 500GB Samsung 870 on the utility node.
2. `techtales-io/terraform-minio`: buckets `cnpg` (exists) subpath, `forgejo-data` (restic),
   `forgejo-dump`; append-only S3 users per leg; write keys to OpenBao (utility mount) per §9.
3. PocketID: create OAuth client (redirect `https://git.utility.techtales.io/user/oauth2/pocket-id/callback`);
   store client id/secret in OpenBao.
4. Register runner on Forgejo UI → token to OpenBao.
5. Restore drill on scratch hardware before declaring done (ADR acceptance gate).

## 11. Non-goals

Public ingress, mail, redis/valkey, TopoLVM, NFS for /data, DR standby (phase 2), mirror config
per-repo (runtime), runner autoscaling.
