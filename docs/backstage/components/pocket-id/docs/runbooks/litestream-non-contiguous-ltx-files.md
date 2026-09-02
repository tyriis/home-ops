# Litestream: Non-Contiguous LTX Files

## Overview

Litestream replicates SQLite WAL changes as LTX files to S3-compatible storage.
This runbook covers the **Litestream v0.5.x storage model** (the cluster runs
`litestream/litestream:0.5.16`). Two distinct failure modes produce a
"non-contiguous ltx files" restore error:

1. **A genuine gap in the replica chain** — a file is missing from the S3
   replica, so a contiguous chain cannot be calculated.
2. **A divergent lineage** — the litestream sidecar silently stopped
   replicating while the live DB kept running, producing two independent TXID
   lineages. This is the failure mode we actually hit in production.

Both are covered below. **Do not attempt to repair either by manually deleting
LTX files with a regex** — see [Remediation](#remediation).

**Owner:** Platform / SRE Team

## Alert Severity and Impact

| Attribute | Value                                                                                                                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Severity  | critical                                                                                                                                                                                                |
| Pages     | yes                                                                                                                                                                                                     |
| Impact    | Database restore from backups is broken. If the primary database is lost, data after the gap position is unrecoverable. The application may be running on its current state but has no reliable backup. |

## Litestream v0.5.x Storage Layout

The v0.5.x model organizes LTX files into **compaction levels** (not
"generations"). There are no "generation directories", no "shadow files", and
no `snapshot-*.ltx` files.

| Directory | Level | Contents                                                      |
| --------- | ----- | ------------------------------------------------------------- |
| `0000/`   | L0    | Raw LTX files (no compaction), written directly from the WAL  |
| `0001/`   | L1    | Compacted every 30s                                           |
| `0002/`   | L2    | Compacted every 5m                                            |
| `0003/`   | L3    | Compacted every 1h                                            |
| `0009/`   | L9    | **Snapshots** (`SnapshotLevel = 9`) — full database snapshots |

Snapshot files in `0009/` are named like any other LTX file, e.g.
`0000000000000001-00000000000b7234.ltx`. There are no `snapshot-*.ltx` files.

**Filename format**: `%016x-%016x.ltx` (16 lowercase hex chars each), e.g.
`0000000000000001-00000000000b7234.ltx`. Regex:
`^([0-9a-f]{16})-([0-9a-f]{16})\.ltx$`.

**Restore anchoring**: `CalcRestorePlan` anchors to the **newest** snapshot in
`0009/` and **never falls back** to an older snapshot. If the newest snapshot's
chain is broken, restore errors with "non-contiguous ltx files" — it does not
fall back to an older, intact snapshot.

## Prerequisites

- `mc` (MinIO Client) installed and configured with an alias that has **read + delete** access to the S3 bucket.
- `kubectl` configured with access to the cluster.
- The exact error message from the application logs.
- Shell with `set -o pipefail` support (bash/zsh).

> **Note on `mc` aliases**: The alias used in this repo, `litestream-pocket-id-ro`,
> is **read-only**. Deleting the S3 replica contents (Failure Mode B) requires a
> **write-capable** alias/credentials. Read-only operations (listing, dry-run
> restore) work with the existing alias.

## Verification

1. Verify S3 access:

   ```bash
   mc ls <ALIAS>/
   ```

2. Check the restore error in the application logs:

   ```bash
   kubectl logs <pod-name> -c litestream-restore --tail=50
   ```

3. List the compaction levels in the S3 bucket:

   ```bash
   mc ls <ALIAS>/<BUCKET>/<DB-PATH>/
   # e.g. mc ls litestream-pocket-id-ro/litestream/pocket-id/pocket-id.db/
   ```

   You should see `0000/`–`0003/` (compaction levels) and `0009/` (snapshots).

4. **Diagnose with a dry-run restore BEFORE touching anything** — this shows the
   exact restore plan (which snapshot, which files, where the gap is):

   ```bash
   litestream restore -dry-run -config /etc/litestream.yml /app/data/pocket-id.db
   ```

   The plan lists the snapshot and LTX files it would apply, and the final
   position. A gap appears as a "non-contiguous ltx files" error here.

## Diagnostic Commands

- **Full bucket listing**: `mc ls <ALIAS>/<BUCKET>/<DB-PATH>/ --recursive`
- **File timestamps** (check whether the S3 chain is still advancing):

  ```bash
  mc ls <ALIAS>/<BUCKET>/<DB-PATH>/0000/ | sort
  ```

  If the newest file timestamps are stale (e.g. weeks old), the sidecar has
  stopped replicating — see [Failure Mode B](#failure-mode-b--divergent-lineage--sidecar-stopped-replicating).

- **Check the live DB's replicated position** (`_litestream_seq`):

  ```bash
  kubectl exec <pod> -n <namespace> -c app -- \
    sqlite3 /app/data/pocket-id.db "PRAGMA wal_checkpoint; SELECT * FROM _litestream_seq;"
  ```

  Compare this against the max TXID in the S3 chain. If the live DB's position
  is far **below** the S3 chain max, the two have diverged into separate
  lineages.

- **Common cause (Failure Mode A)**: A WAL snapshot upload was interrupted
  (pod killed, network blip, OOM) while Litestream was writing the LTX file
  covering the missing position. Check for pod OOMs around the gap time:

  ```bash
  kubectl top pod <pod-name> -n <namespace> 2>/dev/null
  kubectl logs <pod-name> -c litestream --tail=50 -n <namespace> | grep -i error
  ```

## Remediation

> ⚠️ **Data loss**: Removing files from S3 is **permanent and irreversible**.
> Data after the gap position cannot be restored from backups. If the
> application is still running, its live SQLite database may contain the
> missing data — proceed carefully.
>
> ⚠️ **Do NOT manually delete LTX files by regex.** The v0.5.x layout makes
> regex-based deletion unsafe and ineffective: it misses files that span the
> gap, misses `0003/` (L3) and `0009/` (snapshots) entirely, and leaves newer
> snapshots in `0009/` that anchor restore to a broken chain. Use the supported
> recovery paths below.

Set these variables for your environment (edit the values):

```bash
ALIAS="litestream-pocket-id-ro"                     # mc alias name (read-only)
BUCKET="litestream"                                  # S3 bucket name
DBPATH="pocket-id/pocket-id.db"                      # path inside bucket
NAMESPACE="secops"                                   # Kubernetes namespace
POD="pocket-id"                                      # pod name
BACKUP_DIR="${HOME}/litestream-backup-$(date +%Y%m%d-%H%M%S)"  # disk-backed path
```

### Failure Mode A — Genuine gap in the replica chain

The S3 chain has a missing file, but the replica itself is otherwise intact
(the sidecar is still replicating and the chain is advancing). The error looks
like:

```text
cannot calc restore plan: non-contiguous ltx files: have up to <POS> but next file starts at <POS>
```

#### Step 1: Confirm the replica is intact

Run a dry-run restore to see the exact plan and where the gap is:

```bash
litestream restore -dry-run -config /etc/litestream.yml /app/data/pocket-id.db
```

Confirm the S3 chain is still advancing (new files appear in `0000/` over
time). If the chain is **stale**, this is really Failure Mode B — skip to that
section.

#### Step 2: Reset local Litestream state

The supported recovery for a broken local chain is `litestream reset`, which
clears local state so the next sync re-establishes from the replica. **Only use
this when the replica is intact.**

```bash
# Preview what would be reset (no changes):
litestream reset -dry-run -config /etc/litestream.yml /app/data/pocket-id.db

# Perform the reset:
litestream reset -config /etc/litestream.yml /app/data/pocket-id.db
```

This removes local LTX files from the metadata directory, forcing Litestream to
create a fresh snapshot on the next sync. The database file itself is not
modified.

#### Step 3: Verify

```bash
litestream restore -dry-run -config /etc/litestream.yml /app/data/pocket-id.db
```

The plan should now be contiguous and end at the current position.

> **If the replica itself is broken** (the gap is in S3, not just local state),
> `litestream reset` will not help — the cleanest recovery is to rebuild from
> the live DB as described in [Failure Mode B](#failure-mode-b--divergent-lineage--sidecar-stopped-replicating).

### Failure Mode B — Divergent lineage / sidecar stopped replicating

This is the failure mode we actually hit. The litestream sidecar silently
stopped replicating while the live DB kept running, so the live DB and the S3
replica diverged into two lineages with different TXID sequences.

#### Symptoms

- The S3 chain stops advancing — file timestamps in `0000/` are stale (we saw
  a chain frozen for over a month).
- The live DB's `_litestream_seq` position is far **below** the S3 chain's max
  position.
- New writes to the live DB are uploaded as L0 files at a **lower** TXID than
  the existing S3 chain max, creating a parallel lineage that a restore never
  picks up (restore anchors to the newest snapshot).
- Restores return **stale** data — the injected data exists only in the live
  DB, never in S3.

> ⚠️ The live DB lives in an **emptyDir** (`/app/data`), which is **wiped on
> pod restart**. If the pod restarts while the S3 replica is empty or stale,
> the data is lost. Back it up first.

#### Step 1: Back up the live DB FIRST

The live DB is the only place the data exists. Copy it out of the pod before
touching anything:

```bash
kubectl cp "${NAMESPACE}/${POD}:/app/data" "${BACKUP_DIR}" -c app
```

Verify the backup contains the data you care about (e.g. the injected data):

```bash
sqlite3 "${BACKUP_DIR}/pocket-id.db" "SELECT ... FROM <table> WHERE <condition>;"
```

#### Step 2: Delete the entire S3 replica contents

This requires a **write-capable** `mc` alias (the repo's `litestream-pocket-id-ro`
is read-only):

```bash
mc rm --recursive --force <WRITE_ALIAS>/<BUCKET>/<DBPATH>/
```

#### Step 3: Restart the litestream sidecar

The sidecar has `restartPolicy: Always`, so killing PID 1 restarts it. On
restart it re-snapshots the live DB into the now-empty bucket, producing a
fresh contiguous lineage:

```bash
kubectl exec "${POD}" -n "${NAMESPACE}" -c litestream -- kill 1
```

> ⚠️ **CRITICAL**: Between deleting S3 (Step 2) and the sidecar re-snapshotting
> (Step 3), if the pod restarts, the emptyDir is wiped **and** S3 is empty =
> **total loss**. Do Steps 2 and 3 back-to-back.

#### Step 4: Verify the new lineage

```bash
# A new snapshot appears in 0009/:
mc ls <WRITE_ALIAS>/<BUCKET>/<DBPATH>/0009/

# L0 files advance in 0000/:
mc ls <WRITE_ALIAS>/<BUCKET>/<DBPATH>/0000/ | sort | tail -5

# A dry-run restore shows a contiguous plan ending at the current position:
litestream restore -dry-run -config /etc/litestream.yml /app/data/pocket-id.db
```

#### Step 5: Verify the data is actually in the bucket

Restore to a scratch file and check for the injected data:

```bash
litestream restore -config /etc/litestream.yml -o /tmp/verify.db /app/data/pocket-id.db
sqlite3 /tmp/verify.db "SELECT ... FROM <table> WHERE <condition>;"
```

## Escalation

| Contact           | When                                                                        |
| ----------------- | --------------------------------------------------------------------------- |
| Platform Team     | If the restore still fails after following the remediation steps            |
| Application Owner | Notify about potential data loss (changes after the gap timestamp are lost) |

## Prevention

- **Monitor that the S3 chain is advancing.** Alert on stale LTX file
  timestamps in `0000/` — a frozen chain is the earliest sign of a stopped
  sidecar.
- **Monitor the sidecar process.** Add a liveness probe for the litestream
  sidecar so a silent stop is caught immediately.
- **Monitor `_litestream_seq` divergence.** Alert if the live DB's replicated
  position falls behind the S3 chain max.
- Increase Litestream health checks and resource limits to prevent OOM-killed
  uploads.
- Consider a disk-backed (PVC) copy of the DB in addition to the emptyDir, so a
  pod restart does not wipe the only live copy.

## Related Links

- [Litestream Documentation](https://litestream.io)
- [Litestream GitHub Issues](https://github.com/benbjohnson/litestream/issues)
- [Litestream S3 Config](https://github.com/tyriis/home-ops/blob/main/kubernetes/utility/apps/secops/pocket-id/app/litestream.yaml)
- [Pocket-ID HelmRelease](https://github.com/tyriis/home-ops/blob/main/kubernetes/utility/apps/secops/pocket-id/app/helm-release.yaml)
