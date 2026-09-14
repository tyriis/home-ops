# Forgejo on Utility Cluster — Implementation Plan

> **For agentic workers:** Execute task-by-task; each task ends with a commit. Commits follow repo
> GIT_COMMIT rules: `<type>(<scope>): <desc> #10489`, scope mandatory. Implementers are authorized
> to add lint/format fixes (prettier/yamllint/markdownlint) required by CI.

**Goal:** Deploy Forgejo on the utility cluster per ADR-0014 / spec
`docs/superpowers/specs/2026-09-14-forgejo-utility-cluster-design.md`.

**Architecture:** CNPG Postgres (1 inst, barman-cloud WAL→S3) + forgejo-helm chart (1 replica,
no cache, no mail, OIDC-only) on `local-nvme`; VolSync restic + nightly dump for `/data`;
act_runner on main; Gatus static probe from main.

**Tech:** Flux Kustomizations, bjw-s app-template 5.1.0 (house style), CNPG 0.29.0 +
barman-cloud plugin v0.15.0, official `code.forgejo.org/forgejo-helm/forgejo` chart,
VolSync 0.16.0, external-secrets/OpenBao.

**Manual prereqs (outside repo, do NOT implement — task 8 lists them for the human).**

Conventions for ALL new utility files (verbatim patterns from spec §1–2): namespace.yaml with
`kustomize.toolkit.fluxcd.io/prune: disabled`; `<ns>/kustomization.yaml` with
`components: [../../../components/flux/alerts]`; per-app `flux-sync.yaml` + `app/`.

---

### Task 1: CNPG substrate on utility

**Files:** create `kubernetes/utility/apps/cnpg-system/{namespace.yaml,kustomization.yaml}` and
`cnpg-system/cnpg/` mirroring main's chain (spec §2): `flux-sync.yaml` (5 Kustomizations:
cnpg-operator, cnpg-crds, cnpg-barman-cloud-crds, cnpg-barman-cloud, cnpg-cluster),
`git-repository.yaml`, `operator/{helm-repository,helm-release}.yaml`,
`crds/kustomization.yaml`, `barman-cloud/{helm-release.yaml,values.yaml?}` per main's shape.

Port from main: copy `kubernetes/main/apps/cnpg-system/cnpg/*` structures — **adapt**:
keep the operator prometheus-rule (utility runs kube-prometheus-stack), drop `dbman` (main-only,
absent on utility), `cnpg-cluster` flux-sync dependsOn `[cnpg-operator, cnpg-crds,
cnpg-barman-cloud]`, barman dependsOn `cert-manager-issuers` in `cert-manager` ns (exists on
utility). Same versions as main: operator chart 0.29.0, plugin v0.15.0 (git-repository ref tag).

- [ ] Read the 5-6 source files first (`kubernetes/main/apps/cnpg-system/cnpg/**`), then write the
      utility copies.
- [ ] Add `kubernetes/utility/apps/cnpg-system` entry to nothing — Flux scans; only namespace +
      folder required (spec §2).
- [ ] Verify YAML parses: `find kubernetes/utility/apps/cnpg-system -name '*.yaml' -exec yq e '.'
      {} ';'` (must print, not error).
- [ ] Commit: `git add kubernetes/utility/apps/cnpg-system && git commit -m "feat(cnpg): port cnpg substrate to utility #10489"`

### Task 2: forgejo-db cluster + backups CRs

**Files:** create in `kubernetes/utility/apps/cnpg-system/cnpg/cluster/`:
`cluster.yaml` — `forgejo-db`: 1 inst, 20Gi `local-nvme`, `superuserSecret: forgejo-db-superuser`,
`bootstrap: {initdb: {database: forgejo, owner: forgejo}}` (consumes CNPG-conventional secret
`forgejo-db-app`), barman plugin isWALArchiver, `skipEmptyWalArchiveCheck` annotation.
`objectstore.yaml` (`s3://cnpg/utility/forgejo/`, endpoint `https://s3.techtales.io`, secret
`forgejo-db-s3`). `scheduled-backup.yaml` (@daily, method plugin). Three ExternalSecrets
(openbao-backend store): `forgejo-db-superuser` ←
`infra/kubernetes/utility/cnpg-system/forgejo-db-superuser`; `forgejo-db-s3` ←
`infra/kubernetes/utility/cnpg-system/forgejo-db-s3`; `forgejo-db-app` ←
`infra/kubernetes/utility/forgejo-system/forgejo/db` (data keys: `username`, `password`,
CNPG app-secret convention).

- [ ] Copy shapes from `kubernetes/main/apps/cnpg-system/cnpg/cluster/` and
      `kubernetes/main/apps/media/immich/database/` (smaller example), adapt names/spec §4.
- [ ] Commit: `git commit -m "feat(cnpg): add forgejo-db cluster with barman backups #10489"`

### Task 3: envoy SSH TCPRoute support

**Files:** modify `kubernetes/utility/apps/networking/envoy-gateway/config/gateway.yaml` — add
TCP listener (name `ssh`, port 22, protocol TCP, `allowedRoutes: {namespaces: {from: All}}`).

- [ ] Verify with `yq e '.spec.listeners' ...gateway.yaml` — 3 listeners.
- [ ] Commit: `git commit -m "feat(envoy): add tcp listener for git ssh #10489"`

### Task 4: forgejo-system namespace + app

**Files:** `kubernetes/utility/apps/forgejo-system/{namespace.yaml,kustomization.yaml}`,
`forgejo/flux-sync.yaml` (APP=forgejo; dependsOn `cnpg-cluster`(cnpg-system),
`envoy-gateway`(networking), `external-secrets-stores`(secops); postBuild substitute APP),
`forgejo/app/{kustomization.yaml,helm-repository.yaml,helm-release.yaml,external-secret.yaml,
http-route.yaml,ssh-tcp-route.yaml}`.

- **Chart:** `oci://code.forgejo.org/forgejo-helm/forgejo` tag **17.1.6** via OCIRepository
  (joryirving pattern: `ocirepository.yaml` + chartRef) — pinned 2026-09-14. Image:
  `code.forgejo.org/forgejo/forgejo:16.0.4-rootless` (community-dominant tag).
- **Values:** copy structure from https://raw.githubusercontent.com/bjw-s-labs/home-ops/main/k
  ubernetes/apps/dev/forgejo/app/helmrelease.yaml (adapt, don't adopt their infra):
  disable `postgresql-ha/postgresql/memcached/redis-cluster`; NO cache/queue/session blocks
  (joryirving pattern, spec §5); `persistence: {enabled: true, create: false, claimName:
  forgejo-data}`; database `DB_TYPE: postgres`, `HOST: forgejo-db-rw.cnpg-system.svc.cluster.local:5432`,
  `SSL_MODE: disable`, NAME/USER/PASSWD via `valuesFrom` targetPath → secret `forgejo-db-app`
  (keys username/password); 5-key registration lockout + mailer off + openid signin/signup off;
  `gitea.oauth[]` openidConnect PocketID (`autoDiscoverUrl: https://id.techtales.io/`,
  `existingSecret: forgejo-oidc`, scopes `openid profile email groups`, `adminGroup` TBD from
  PocketID group name — use `forgejo_admins`); bleve indexers; admin `existingSecret:
  forgejo-admin-secret`; `service.ssh.type: ClusterIP`.
- **Routes (plain manifests, not chart route):** `http-route.yaml` HTTPRoute
  `git.utility.techtales.io` → parentRef envoy/networking sectionName https,
  annotation `external-dns/unifi: "true"`, backend forgejo http 80 (service name rendered by
  chart = `forgejo-http`). `ssh-tcp-route.yaml` TCPRoute → parentRef envoy/networking sectionName
  **ssh** (task 3), backend `forgejo-ssh` port 2222 (rootless listen port; public 22 on gateway).
- **ExternalSecrets:** `forgejo-admin-secret` (username/password) ←
  `infra/kubernetes/utility/forgejo-system/forgejo/admin`; `forgejo-oidc` (client_id/client_secret)
  ← `.../forgejo/oidc`. NOTE: chart's valuesFrom for DB wants keys `GITEA__[database]...`? No —
  plain `user`/`passwd` keys via targetPath mapping in ES template (map username→GITEA__[database]
  USER etc. — implement as templated ES producing one secret `forgejo-db-values`).
- [ ] Commit: `git commit -m "feat(forgejo): deploy forgejo on utility #10489"`

### Task 5: VolSync + dump CronJob

**Files:** `forgejo-system/forgejo/app/`: `pvc.yaml` (VolSync bootstrap pattern verbatim from
`kubernetes/components/volsync/pvc.yaml`, substituted inline: name `forgejo-data`, RWO, 50Gi,
storageClassName `local-nvme`, prune-disabled label, dataSourceRef → ReplicationDestination
`forgejo-data`); `replication-destination.yaml` (bootstrap RD per VolSync restore pattern —
`restic.repository: forgejo-data-volsync-minio`, copyMethod Snapshot, snapshotClass/cacheClass
`local-nvme`, capacity 50Gi, moverSecurityContext 1001/1001);
`replication-source.yaml` (schedule `*/15 * * * *`, restic block per
`kubernetes/components/volsync/minio/replication-source.yaml` with local-nvme classes,
`retain: {hourly: 12, daily: 7, weekly: 4, monthly: 3}`);
`external-secret.yaml` add: `forgejo-data-volsync-minio` (RESTIC_REPOSITORY/PASSWORD + AWS_*) ←
`infra/kubernetes/utility/volsync/forgejo-data`; `forgejo-dump-s3` ← `.../forgejo/dump`.
`dump/{cronjob.yaml,role.yaml,rolebinding.yaml,serviceaccount.yaml}`: CronJob `forgejo-dump`
@daily: initContainer = forgejo image, PVC mounted rw, command
`forgejo dump --file /backup/forgejo-dump.zip --skip-logs` (env mirrored from app: DB
valuesFrom + APP_RUN_USER 1001), emptyDir shared `/backup`; container = `minio/mc:latest`
configured from `forgejo-dump-s3` → `mc cp /backup/*.zip s3/forgejo-dump/`. RBAC only if
`forgejo dump` needs DB ping via psql — it does not (direct DB env). No exec sidecar.

- [ ] Commit: `git commit -m "feat(forgejo): add volsync and nightly dump #10489"`

### Task 6: act_runner on main

**Files:** `kubernetes/main/apps/github/forgejo-runners/{namespace.yaml,kustomization.yaml,
act-runner/flux-sync.yaml, act-runner/app/{kustomization.yaml,helm-release.yaml,
external-secret.yaml}}` — main cluster folder per §9 wiring.

- app-template 5.1.0 Deployment, ns `forgejo-runners`: container `runner`
  (`code.forgejo.org/forgejo/runner:v13.1.0` — latest release, verified 2026-09-14)
  command `act_runner daemon --config /etc/act-runner/config.yaml`;
  container `docker-daemon` (`docker:28-dind`), both **privileged**, shared emptyDir `/run`
  (mountPropagation HostToContainer on runner). NOTE privileged = docker runner class per ADR —
  isolated ns, own SA (default), no other-ns secrets.
- Secret `act-runner-config` (ExternalSecret, key
  `infra/kubernetes/main/forgejo-runners/act-runner`, template emits `config.yaml` with
  token + labels `["forgejo:docker"]` + forge URL `https://git.utility.techtales.io`).
- [ ] Commit: `git commit -m "feat(ci): act_runner namespace on main #10489"`

### Task 7: Gatus probe

**Files:** modify `kubernetes/main/apps/observability/gatus/app/resources/config.yaml` — static
endpoint block mirroring the existing `flux-webhook-utility` entry (group, url
`https://git.utility.techtales.io/api/healthz`, conditions STATUS==200, dns-resolver
`tcp://192.168.1.1:53` per existing precedent).

- [ ] Commit: `git commit -m "feat(gatus): forgejo healthz probe #10489"`

### Task 8: validation sweep

- [ ] `task lint:yaml` and `task lint:prettier` — fix and commit
      `style(lint): <desc> #10489` if anything was touched.
- [ ] Cross-file consistency: secret names §9 of spec == ES names created; PVC name
      `forgejo-data` used identically in pvc/RS/chart persistence.claimName; RD name == pvc
      dataSourceRef.

### Task 9: manual prereqs checklist (report to human, no code)

Report these to the human at completion:
1. Verify `/var/mnt/extra` = 500GB Samsung 870 on utility node.
2. terraform-minio: restic bucket + forgejo-dump bucket + per-leg S3 users; OpenBao keys written
   (§9 of spec).
3. PocketID client + OpenBao oidc secret.
4. Register runner → token to OpenBao.
5. Restore drill (ADR acceptance gate).

---

**Ordering:** 1→2 (same folder), 3→4→5 (route before app? no — manifests are order-agnostic for
Flux `dependsOn`; still commit 3 before 4). 6,7 independent — can run parallel with 1–5.

**Validation:** `task lint:yaml`, `task lint:prettier`, full `yq` parse sweep, plus manual diff
review per task. No cluster apply (GitOps-first — Flux reconciles on merge).
