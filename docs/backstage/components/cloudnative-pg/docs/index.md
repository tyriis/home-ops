# CloudNativePG

CloudNativePG (CNPG) is the PostgreSQL operator used across the home-ops clusters. It runs each database as a
`Cluster` custom resource with continuous WAL archiving and plugin-based base backups to S3-compatible object
storage.

## Clusters

All clusters back up to the S3 endpoint `https://s3.techtales.io` in bucket `cnpg`. Credentials are synced from
OpenBao by the External Secrets Operator — no S3 credentials are committed to the repository.

| Cluster      | Namespace                      | Image          | Databases                                                | ObjectStore / Server name   | Destination path             |
| ------------ | ------------------------------ | -------------- | -------------------------------------------------------- | --------------------------- | ---------------------------- |
| `postgres17` | `cnpg-system`                  | PG 17.5        | `app`, `hass`, `firecrawl_nuq` (+ empty legacy `immich`) | `postgres17` / `postgres17` | `s3://cnpg/kube-lab`         |
| `immich-db`  | `media`                        | PG 18 + vchord | `immich`                                                 | `immich-db` / `immich-db`   | `s3://cnpg/main/immich`      |
| `forgejo-db` | `git-system` (utility cluster) | PG 18          | `forgejo`                                                | `forgejo-db` / `forgejo-db` | `s3://cnpg/utility/forgejo/` |

Images: `postgres17` uses `ghcr.io/cloudnative-pg/postgresql:17.5-22`; `immich-db` uses
`ghcr.io/tensorchord/cloudnative-vectorchord:18.3-1.1.1@sha256:392b53675b403d6a2c72b673cc488a7c272514755dd818c622fb9ce4665193c4`;
`forgejo-db` uses a PG 18 image.

Source definitions:

- Operator, plugin and shared cluster: [`kubernetes/main/apps/cnpg-system/cnpg/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/cnpg-system/cnpg)
- Immich database: [`kubernetes/main/apps/media/immich/database/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/media/immich/database)
- Forgejo database: [`kubernetes/utility/apps/git-system/forgejo/database/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/utility/apps/git-system/forgejo/database)

## How backups work

- **Operator**: Helm chart `cloudnative-pg` `0.29.1` (app version `1.30.1`).
- **Backup plugin**: `barman-cloud.cloudnative-pg.io` (plugin-barman-cloud `v0.15.1`, a CNPG-I plugin). Backups
  are plugin-based; there is no in-tree `barmanObjectStore`.
- **Base backups**: every cluster has a `ScheduledBackup` with `schedule: "@daily"` (runs around 02:00),
  `method: plugin` and `backupOwnerReference: self`.
- **WAL archiving**: continuous, with an `ObjectStore` `retentionPolicy: 30d` on each cluster. The continuous WAL
  window is therefore about 30 days.
- **Credentials**: External Secrets Operator syncs bucket credentials from OpenBao into the Kubernetes secrets
  `postgres17-s3`, `immich-s3` and `forgejo-db-s3` (keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
- **Object storage**: S3-compatible endpoint `https://s3.techtales.io`, bucket `cnpg`.

Backup health is reported by the barman-cloud plugin metrics. Watch these in particular:

| Metric                                                           | Meaning                                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp` | Timestamp of the most recent successful (available) base backup.            |
| `barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp`    | Timestamp of the most recent failed backup. Any recent value is a red flag. |
| `barman_cloud_cloudnative_pg_io_first_recoverability_point`      | Oldest point to which the cluster can currently be recovered.               |

## Restore verification

An unverified backup is no backup. Run the periodic restore drill so we know the backups are actually restorable:

- [Restore Verification runbook](runbooks/restore-verification.md)

## Notes / gotchas

- **`serverName` must match the source folder.** `externalClusters[].plugin.parameters.serverName` must equal the
  folder the source cluster actually wrote to (e.g. `postgres17`, `immich-db`). The commented recovery stub in
  `kubernetes/main/apps/cnpg-system/cnpg/cluster/cluster.yaml` still references a stale `serverName: main-postgres17`;
  a restore using that value fails with "no backups found".
- **No trailing slash in `destinationPath`.** A trailing slash makes barman send a double-slash prefix (e.g.
  `kube-lab//`) which MinIO rejects. The `forgejo-db` `ObjectStore` is the one remaining path with a trailing slash.
- **`skipEmptyWalArchiveCheck`.** Both production clusters carry the
  `cnpg.io/skipEmptyWalArchiveCheck: "enabled"` annotation. Without it, bootstrap can stall with
  `WAL archive check failed ... Expected empty archive`.
- **Dead legacy database.** `postgres17.immich` is an empty legacy database (about 7.5 MB, zero relations) left
  over from the pre-June-2026 dbman era. Immich's live database is `immich-db` (about 56k assets).

## Related

- [Issue #10706 — CNPG backups failing since 2025-10](https://github.com/tyriis/home-ops/issues/10706)
- [CloudNativePG documentation](https://cloudnative-pg.io/documentation/)
