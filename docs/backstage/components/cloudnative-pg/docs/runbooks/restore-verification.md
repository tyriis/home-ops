# Restore Verification

## Overview

A backup that has never been restored is an assumption, not a backup. This runbook is the periodic
**restore drill** for the CNPG clusters: it boots a throwaway, isolated cluster from the production
backup objects and proves both that the data is structurally the same database and that it contains
the expected rows.

The drill exists because of [issue #10706](https://github.com/tyriis/home-ops/issues/10706), where
backups silently failed for roughly 11 months:

- There was no bucket-level `s3:ListBucket` for the `cnpg` users, so writes passed but listings were denied.
- A trailing slash in one `destinationPath` made barman send a double-slash prefix (`kube-lab//`) that
  MinIO rejects.

`postgres17` had no completed backup from 2025-10-17 until the fix, and `immich-db` never completed.
Both were fixed and backups resumed. The outstanding acceptance item — "an unverified backup is no
backup" — is satisfied by running this drill. Treat a successful drill as the restoration acceptance
criterion for CNPG: it is not complete until a restore has been exercised and checked.

**Owner:** Platform / SRE Team

## Prerequisites

- An **admin** kubeconfig. The restore drills create and delete CNPG `Cluster` resources and exec into
  pods, which the read-only service account cannot do (see the RBAC note below).
- The `kubectl cnpg` plugin, version `1.30.x` to match the operator (`1.30.1`):

  ```bash
  yay -S kubectl-cnpg
  kubectl cnpg version
  ```

- `kubectl` configured to reach the cluster that hosts the target databases.

> **RBAC limitation**: the `kube-tools:kubectl-readonly` service account **cannot** `pods/exec`,
> `pods/proxy`, or create/delete CNPG `Cluster` resources. Apply and delete the drill manifests, and
> run `cnpg psql`, with an admin context.

## The drill manifests

The drill manifests were created alongside this runbook and are **manual-apply only**. They are
deliberately **not** referenced by any `kustomization.yaml`, so Flux never applies them. Each one
bootstraps a new `Cluster` from the production backup via `spec.bootstrap.recovery.source` and an
`externalClusters[]` entry using the barman plugin.

| Manifest                                                            | Restored cluster     | Verifies                                                                                     |
| ------------------------------------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------- |
| `kubernetes/main/apps/cnpg-system/cnpg/cluster/restore-verify.yaml` | `postgres17-restore` | All `postgres17` databases (`app`, `hass`, `immich`, `firecrawl_nuq`) are recoverable.       |
| `kubernetes/main/apps/media/immich/database/restore-verify.yaml`    | `immich-db-restore`  | The PG 18 + VectorChord Immich database is recoverable with the `vchord` extension loadable. |

Both restored clusters are single-instance and set `enableSuperuserAccess: true` so `kubectl cnpg psql`
works. They are **not** archivers (no `spec.plugins`), so a restored cluster can never overwrite
production backup objects.

## Procedure

Work through one manifest at a time. Replace namespaces as noted (`cnpg-system` for `postgres17`,
`media` for `immich-db`).

### 1. Confirm production is currently backing up

Before restoring, confirm the source cluster has a recent successful backup. Use the "Continuous
Backup status" block and the ObjectStore / Server name line:

```bash
kubectl cnpg status postgres17 -n cnpg-system
kubectl cnpg status immich-db -n media
```

Expect a recent **Last Successful Backup** and a server name matching the source folder
(`postgres17`, `immich-db`).

### 2. Apply the drill manifest

```bash
kubectl apply -f kubernetes/main/apps/cnpg-system/cnpg/cluster/restore-verify.yaml
# or
kubectl apply -f kubernetes/main/apps/media/immich/database/restore-verify.yaml
```

### 3. Wait for recovery and promotion

```bash
kubectl cnpg status postgres17-restore -n cnpg-system
# or
kubectl cnpg status immich-db-restore -n media
```

The restore is complete when the cluster reports **Cluster in healthy state** and has been promoted
(no longer in recovery). First bootstrap can take a while as the base backup is downloaded and WAL is
replayed.

### 4. Check the content

#### postgres17-restore

```bash
# List the databases; expect app, hass, immich, firecrawl_nuq
kubectl cnpg psql postgres17-restore -n cnpg-system -- -c '\l'

# Expect f (false) after promotion
kubectl cnpg psql postgres17-restore -n cnpg-system -- -c 'SELECT pg_is_in_recovery();'
```

#### immich-db-restore

```bash
kubectl cnpg psql immich-db-restore -n media -- -d immich -Atc \
  "SELECT count(*), min(\"fileCreatedAt\"), max(\"fileCreatedAt\") FROM asset WHERE \"deletedAt\" IS NULL"
```

Expect roughly `56457` assets, with the oldest `fileCreatedAt` around `1999-05-07` and the newest close
to the present.

### 5. Tear down the drill

The restored cluster is throwaway. Delete it as soon as the checks pass so it does not consume
resources or PVC space:

```bash
kubectl delete -f kubernetes/main/apps/cnpg-system/cnpg/cluster/restore-verify.yaml
# or
kubectl delete -f kubernetes/main/apps/media/immich/database/restore-verify.yaml
```

## Interpreting results

- **System ID match is the strongest structural proof.** The restored cluster's PostgreSQL System ID
  must equal the production cluster's — the drill observed `7547851034227179550` for both. A matching
  System ID proves the restored data directory is the same database lineage, not a coincidence. You can
  read it with:

  ```bash
  kubectl cnpg psql postgres17-restore -n cnpg-system -- -c 'SELECT system_identifier FROM pg_control_system();'
  ```

- **The content check is the functional proof.** The database list / row counts / timestamp bounds show
  the data actually survived, not just that the files look like a PostgreSQL data directory.
- **One WAL segment caveat.** A restore reaches the last **archived** WAL. Transactions sitting in the
  currently-active, not-yet-archived WAL segment are legitimately absent, so the newest content may lag
  production by a small amount. Watch for `WALs waiting to be archived: 0` as the healthy steady state
  on production; a single failed timeline-history WAL (for example `00000044.history` during a
  switchover) does not block recovery when the newest base backup already contains it.

## Troubleshooting

### Restore fails with "no backups found"

`serverName` does not match the folder the source wrote to. The recovery stub in
`kubernetes/main/apps/cnpg-system/cnpg/cluster/cluster.yaml` references a stale `main-postgres17` — don't use it.
Confirm the value with `kubectl cnpg status <cluster> -n <ns>`, looking at the "Continuous Backup status" line.

### Bootstrap stalls with `WAL archive check failed ... Expected empty archive`

Add `cnpg.io/skipEmptyWalArchiveCheck: "enabled"` to the restored cluster. Both production clusters carry it.

### `vchord` extension cannot load in `immich-db-restore`

Set `shared_preload_libraries: [vchord.so]` on the restored cluster to match the source.

### A timeline-history WAL (e.g. `00000044.history`) is missing

Usually harmless when the newest base backup already contains it; recovery proceeds. Only escalate if recovery stalls.

### `cnpg psql` / apply / delete fails with permission errors

You are on the read-only service account. Drills require an admin context (see Prerequisites).

### Barman writes rejected by MinIO

Check `destinationPath` for a trailing slash. A trailing slash produces a double-slash prefix that MinIO
rejects; `destinationPath` must have no trailing slash.

## Related links

- Drill manifests: [`cnpg/cluster/restore-verify.yaml`](https://github.com/tyriis/home-ops/blob/main/kubernetes/main/apps/cnpg-system/cnpg/cluster/restore-verify.yaml), [`immich/database/restore-verify.yaml`](https://github.com/tyriis/home-ops/blob/main/kubernetes/main/apps/media/immich/database/restore-verify.yaml)
- Source definitions: [`kubernetes/main/apps/cnpg-system/cnpg/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/cnpg-system/cnpg)
- [Issue #10706 — CNPG backups failing since 2025-10](https://github.com/tyriis/home-ops/issues/10706)
- [CloudNativePG recovery documentation](https://cloudnative-pg.io/documentation/current/recovery/)
