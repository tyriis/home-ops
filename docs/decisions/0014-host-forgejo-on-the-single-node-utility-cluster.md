---
status: accepted
date: 2026-09-13
decision-makers: [tyriis]
---

# Host Forgejo on the single-node utility cluster

## Context and Problem Statement

We want to self-host Forgejo as our git forge. Primary driver is independence from GitHub/cloud —
some repos will never be mirrored, so the forge is their only copy and backup is a first-class
requirement. Secondary requirements:

- Availability 24/7 ("HA" discussed and re-scoped — see Decision).
- Isolation: NAS data (TrueNAS/Aostar media, photos, personal data) must never be put at risk by
  forge workloads or their vulnerabilities.
- Restore independence: being able to rebuild the forge on arbitrary hardware without our own
  cluster, NAS, or cloud being alive.
- Fit declarative IaC (Flux/SOPS in home-ops).

Candidate systems (decision matrix scored on weighted criteria, max 36):

| System                      | Score | Shape                                                                |
| --------------------------- | ----- | -------------------------------------------------------------------- |
| ms01 (3-node Talos cluster) | 29    | HA-capable, heavy stack                                              |
| utility (1-node Talos)      | 28    | always-on, minimal, already runs PocketID/envoy                      |
| Aostar NAS (TrueNAS, ZFS)   | 17    | best hardware fit, isolation score 0 — disqualified by requirement 2 |
| ZimaBoard 1 (16GB)          | 25    | SQLite+Litestream idea; no HA, no growth headroom                    |

## Decision Drivers

- Independence from GitHub/cloud; unrepositoried repos make the forge their only copy.
- Backup/restore as a first-class requirement, not an afterthought.
- 24/7 availability for 2 users.
- Isolation of NAS data from forge workloads and their vulnerabilities.
- Restore independence from cluster, NAS, and cloud.
- Fit the existing declarative IaC workflow (Talos/talhelper, Flux, SOPS).

## Considered Options

- **utility cluster** (1-node Talos, always-on) + CNPG Postgres, 1 instance, local PV, one-way
  backups to S3 — _chosen_
- ms01 cluster (3-node Talos) + CNPG 3 replicas + shared storage for `/data`
- Forgejo directly on Aostar NAS (TrueNAS Docker/apps)
- SQLite + Litestream on ZimaBoard 1
- ZimaBoard + NAS NFS for `/data`
- 2nd app replica across clusters (utility↔ms01)

## Decision Outcome

Chosen option: **Host Forgejo on the utility cluster (single-node Talos, always-on)**, because it
keeps the git host free of any dependency on the home-ops cluster, matches the minimal-stalk
footprint of a 2-person forge, and delivers the re-scoped availability model (see Consequences)
through backup discipline instead of shared-storage HA.

Concrete parameters:

- **CNPG Postgres, exactly 1 instance.** The operator is kept for barman-cloud backups/PITR and
  declarative config, not for HA — replicas on one node share one failure domain and buy nothing.
- **500GB internal SSD, local PV** (TopoLVM or hand-written local PV). DB and `/data` both local.
  No Rook-Ceph, no Longhorn, no NFS mount of the NAS into the forge pod.
- **1 app replica. Zero mail** (OIDC-only auth, `DISABLE_REGISTRATION`, `mailer.ENABLED=false`).
  Notifications via native Discord webhooks. No Valkey/Redis needed at 1 replica.
- **Backup = the real HA strategy**, three one-way legs to S3 (MinIO at `s3.techtales.io`) backed
  by the Aostar NAS, with the Synology DS218 as the offsite copy of the buckets: barman (DB, WAL,
  ~sec RPO), VolSync restic of `/data` (≤15 min RPO), nightly forgejo dump (24h RPO, whole-app
  escape hatch). Append-only/restic-repo-key credentials. **Acceptance gate: one timed restore
  drill on scratch hardware.**
- **CI runners (`act_runner`) on ms01**, separate namespace, quotas, treated as untrusted-exec.
  Pull-based, so forge outages only pause new jobs.
- **Optional per-repo GitHub push mirrors** — cloud becomes the convenience copy; the forge is
  primary.
- **Renovate policy:** digest/minor bumps automerge (restart blip of 10–40s is accepted as the cost
  of this simplicity); semver-major bumps gated for manual review because they run irreversible DB
  migrations.

### Consequences

Positive:

- Forge does not depend on the home-ops cluster (or vice versa) — the git host survives a ms01
  outage and has no recursive infra dependency.
- Isolation holds in both directions: NAS never gets a rw mount from an internet-adjacent workload;
  only S3 backup traffic crosses.
- Restore-anywhere: binary + dump (or PITR + restic) on any Linux box; no k8s needed to recover.
- Minimal moving parts on the box: CNPG + Forgejo + VolSync operators. No distributed storage to
  operate.
- Matches existing Talos/Flux/SOPS workflow.

Negative / accepted risks:

- No node-level HA. Utility node death = forge down until restore or hardware repair (target:
  minutes–1h, RPO as above). Explicitly accepted for a 2-person forge; git clients queue offline.
- Local single disk: disk death = restore event (mitigated by backup design + the drill).
- Renovate minor updates cause brief restarts (accepted; see policy).
- VolSync is used as a declarative restic driver rather than for its cross-cluster feature — mild
  tool mismatch, accepted for CRD symmetry with CNPG.
- Discord.com is a deliberate egress dependency for notifications.

Revisit triggers:

- Uptime dissatisfaction → phase-2 options: same-node 2nd replica + Valkey queue (zero-downtime
  updates), or CNPG standby on ms01 (DB DR). Both have a split-brain guard requirement:
  DNS/promotion is a single explicit human action.
- More stateful workloads land on utility → reconsider storage substrate.
- Forge becomes org-critical (teams, external contributors) → re-evaluate HA seriously.

## Pros and Cons of the Options

| Alternative                                     | Killed by                                                                                                                                                                            |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ms01 cluster + CNPG 3 replicas + shared storage | Needed RWX for `/data` → back to Ceph/Longhorn ("overkill"); forge inherits full-cluster dependency; isolation from NAS only via NFS-into-big-cluster, which widens the blast radius |
| Rook-Ceph for shared `/data`                    | Operational weight disproportionate to 2 users; Renovate PR backlog already shows it as friction                                                                                     |
| Longhorn                                        | Simpler than Ceph but still a distributed storage control plane for one PVC                                                                                                          |
| Forgejo directly on Aostar NAS (Docker/apps)    | Violates core requirement 2: forge tooling + NAS data on one box                                                                                                                     |
| SQLite + Litestream on ZimaBoard                | Best restore-independence, worst HA/growth; Litestream covers DB only, repos still need restic; hardware too small for a year of growth                                              |
| ZimaBoard + NAS NFS for `/data`                 | Same NFS-into-app trust problem, plus SQLite-on-NFS is corrupt-unsafe — forces Postgres anyway                                                                                       |
| 2nd app replica across clusters (utility↔ms01)  | Requires storage crossing node boundary → re-imports NFS-isolation or distributed-storage complexity; two "live-looking" forges invite split-brain                                   |

## More Information

- Decision basis: decision matrix (2026-09-13) evaluating ms01 3-node / utility 1-node Talos /
  Aostar NAS / ZimaBoard; ms01 29 vs utility 28 is within noise — the runner split recovers ms01's
  headroom where it matters. The full plan and matrix script live in external notes
  (`2026-09-13-forgejo-utility-cluster-plan.md`, `2026-09-13-forgejo-decision-matrix.py`), not in
  this repository.
- Decision research assisted by the Hermes agent.
- Post-decision clarifications (same session):
  - "HA" was re-scoped from failure-transparent to disk-redundant + fast-recoverable +
    one-way-backup-isolated, which is what the utility+backup design actually delivers.
  - CNPG single-instance with barman was chosen over bare Postgres + `pg_dump` cron: PITR ergonomics
    and declarative config outweigh the operator surface.
  - Litestream/WAL-G/Walrey ruled out as not applicable: WAL archiving is CNPG's barman-cloud
    plugin; no SQLite survives in this design.
- Talos caveat: if `hostPath` were used for the 500GB disk (dual-pod sharing), Talos host path
  protection requires `allowedHostPaths` in machine config via talhelper. Prefer TopoLVM/local PV —
  no exception needed, cleaner lifecycle.
