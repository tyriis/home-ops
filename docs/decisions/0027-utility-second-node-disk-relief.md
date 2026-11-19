---
status: accepted
date: 2026-11-19
decision-makers: [tyriis]
---

# Relieve utility disk pressure with a second node (ZimaBlade worker)

## Context and Problem Statement

util01 (single-node control plane) keeps etcd, the control plane, Flux,
OpenBao, Pocket-ID, Harbor, Forgejo + Postgres, Opengist, and the full
observability stack on one 500 GB system disk. The system disk carries
~270 GB of mixed workload state — registry blobs, TSDB, database files —
and disk pressure events hit the control plane and its etcd member, the
worst possible blast radius.

## Options Considered

- **Larger system disk in util01**: one more single point of failure, still
  mixes control plane with heavy I/O, does nothing for CPU/RAM contention
  during observability compaction.
- **Attach external storage (NAS/NFS)**: puts cluster databases behind a
  protocol with the worst fsync behaviour; NAS is also main-cluster's
  backup target — new failure coupling.
- **Second node** (chosen): an IceWhale ZimaBlade (Celeron N3450, 16 GB) that
  already owns 480 GB + 500 GB SATA. Splits workloads across two failure
  domains, gives heavy services their own disks, and leaves util01's system
  disk carrying only control-plane state (~15 GB target).

## Decision

Run util02 as a Talos worker in the utility cluster. Workload classes:
git/state services (Forgejo + Postgres, Opengist) migrate with volsync
backups as the gate; observability re-provisions empty (data is
rebuildable); Harbor moves last and re-provisions empty (registry content
is re-pullable via its pull-through caches).

Both nodes get a Talos **user volume** named `data` on their secondary SSD,
the basis for a shared `local-ssd` StorageClass so node-local data is
addressed by volume, not path.

## Consequences

- util01 apply/etcd events no longer coincide with TSDB compactions.
- Two nodes to patch instead of one; scheduling gains node-spread concerns
  (CNPG primary/replica now land per-node on local disks).
- Worker installs surfaced hard requirements now written into the system
  docs: wwID-only disk pinning, control-plane-only patch split per role, and
  reading live disk attributes before pinning.
- N3450 is weak on crypto — volume encryption stays off on util02 by
  design; the data is volsync-replicated to S3 instead.
