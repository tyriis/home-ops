---
status: accepted
date: 2026-09-05
decision-makers: [tyriis]
---

# Run olah on TrueNAS as the Hugging Face model cache

## Context and Problem Statement

The two inference systems (1 TB local NVMe each) and the cluster are used to experiment with a rotating set of large LLM checkpoints (Qwen/DeepSeek/GLM class; tens to hundreds of GB per repo).
The local NVMe fills regularly; freeing space requires deleting local model copies, and re-testing a previously used model
then forces a full re-download from huggingface.co — slow over the uplink, rate-limited, and wasteful, because the bytes are byte-identical to what we already fetched once.

We need a LAN-resident Hugging Face pull-through cache that unmodified HF tooling (`hf` CLI / `huggingface_hub`, `transformers`, vLLM, TEI) reaches by setting `HF_ENDPOINT` alone.
It must transparently handle the modern HF delivery stack (LFS plus the Xet CAS protocol), support gated repositories via client-token pass-through,
and tolerate cache wipes as a normal operating mode (model bytes are disposable data, not primary storage).

Protocol research (Aug–Sep 2026) established that the HF Hub is not OCI-distribution-compatible, so OCI registries cannot pull-through it, and that Dragonfly's `hf://` backend cannot serve native HF clients.
`olah` is, per source-level verification, the only actively maintained open-source mirror that is simultaneously a durable cache, `HF_ENDPOINT`-compatible, Xet-aware, and fail-closed for gated repos.
ADR-0004 established TrueNAS + doco-cd as the home for NAS-resident container services.

## Decision Drivers

- Native `HF_ENDPOINT` compatibility — zero re-packaging, zero client changes beyond an env var
- Durable, on-demand pull-through caching — un-prefetched models must "just work"
- Transparent handling of LFS and Xet delivery, no client-side workarounds
- Gated/licensed models usable without any HF credential stored server-side
- Alignment with ADR-0004: NAS-resident services run as native docker-compose managed by doco-cd
- Bytes live on ZFS (checksums, scrub, snapshots); the cache is disposable by design
- Homelab throughput reality: 4×8 TB RAIDZ2 sequential read and dual-2.5GbE inference-host links, not 10GbE

## Considered Options

- olah as native docker-compose service on TrueNAS via doco-cd
- olah as in-cluster workload with NFS-backed cache
- olah as TrueNAS catalog/custom app
- hugrs as NAS-side HF mirror
- kkRepo `huggingface-proxy` repository type
- Dragonfly (d7y.io) with `hf://` backend
- zot/Harbor OCI route (package models as OCI artifacts)
- Warmer Job only into shared PVC with `HF_HUB_OFFLINE=1`

## Decision Outcome

Chosen option: **olah as native docker-compose service on TrueNAS via doco-cd**, because it is the only evaluated option
that is simultaneously `HF_ENDPOINT`-native, a durable pull-through cache, Xet-aware, gated-capable with zero server-side credentials,
and a natural citizen of the doco-cd/TrueNAS lane established in ADR-0004.

Concrete parameters:

- Deployed as `docker/deploy/hf-cache/` shared compose plus per-host instance, following the doco-cd layout of ADR-0004.
- Image pinned: `xiahan2019/olah:0.5.1` (the shipped compose example references a stale typo tag `lastet`). Exactly oneolah instance — it refuses multiple writers over one cache.
- Cache on a dedicated ZFS dataset (`recordsize=1M`, `atime=off`, default `lz4`), quota **10 TB**; olah `cache-size-limit = "8TB"`,
  `cache-clean-strategy = "LARGE_FIRST"`, `cache-compression = "none"`.
- Exposed as `https://hf.techtales.io` through the existing Nginx Proxy Manager on the NAS (Let's Encrypt via NPM; `proxy_buffering off` and extended read timeouts required for multi-GB streams).olah itself listens plain HTTP on the NAS.
- Clients set `HF_ENDPOINT=https://hf.techtales.io` and supply their own `HF_TOKEN`; olah forwards it upstream and caches gated content per-token
  (client-side entitlement decision). License acceptance for gated models remains tied to the token's account.
- v1 is deliberately minimal: pure on-demand pull-through, no pre-warm/verify jobs; mtime-based LRU eviction is accepted. A warmer CronJob and signed pinned-commit manifests are recorded as known future extensions.

### Consequences

- Good, because wipe-and-re-pull on the inference systems is bounded by the LAN (~250–280 MB/s per flow on the 2.5GbE links, RAIDZ2 sequential ceiling ~400–600 MB/s), not by huggingface.co: a 200 GB re-pull is minutes, not an uplink-bound slog.
- Good, because clients are unmodified — `hf download`, `transformers`, vLLM, TEI all work via one env var; datasets and Spaces are mirrored too.
- Good, because no HF credential ever rests on the NAS: gated downloads use client-token pass-through, andolah's visibility cache is per-token and fail-closed (source-verified).
- Good, because it stays in the ADR-0004 GitOps lane, and its open consequence ("certificate handling outside Kubernetes") is already solved here by NPM + existing DNS records.
- Good, because corruption handling is layered: ZFS checksums + scrub detect/heal bit-rot; olah CRC32-verifies every 1 MiB chunk on serve
  and drops-and-refetches bad blocks.
- Neutral, becauseolah is invisible to Flux/Renovate's in-cluster view; image bumps ride the existing `docker/` Renovate flow.
- Bad, becauseolah is a young v0.x project (277 stars, weekly churn): cache directories are treated as disposable across upgrades (version/CRC mismatch wipes entries), so upgrades cost a re-warm; the tag is pinned to control this.
- Bad, because there is no pinning API: a churn of one-off models can evict a favorite, which then pays a cold re-fetch; mitigated later by the recorded warmer extension.
- Bad, because the first-ever fetch of an unknown model still runs at HF speed, and concurrent large pulls share one RAIDZ2 pool and the NAS uplink.
- Bad, because dataset provisioning, the NPM proxy host, and the DNS record remain manual NAS-side steps outside GitOps (consistent with the ADR-0004 boundary).

### Confirmation

- Acceptance test: `HF_ENDPOINT=https://hf.techtales.io hf download <public repo>` run twice — the second pull completes at LAN speed with no NAS egress, andolah's block store grew only after the first pull.
- Gated test: download of a gated repo succeeds with a token whose account holds the grant and is refused for anonymous clients.
- Deployment evidence: doco-cd reconciles `docker/deploy/hf-cache` on the NAS (`docker compose ps`, doco-cd logs).

## Pros and Cons of the Options

### olah as native docker-compose service on TrueNAS (doco-cd)

- Good, because all four capability drivers are native: `HF_ENDPOINT` drop-in, durable block-level pull-through cache, server-side Xet/LFS handling, gated token pass-through with fail-closed visibility.
- Good, because the cache is a plain ZFS dataset — scrub, snapshots, quota, and disposal all work with existing NAS muscle.
- Neutral, because it is a single-process FastAPI service — right-sized for homelab links, not for datacenter throughput.
- Bad, because v0.x churn means no on-disk format stability between releases (upgrade = re-warm) and a small community.
- Bad, because there is no admin UI, ACLs, or per-repo pinning — cache policy is the config file.

### olah as in-cluster workload with NFS-backed cache

- Good, because Flux, in-cluster DNS, and cert-manager would manage everything.
- Neutral, becauseolah is NFS-safe by design (dedicated `meta.lock` sidecar; the SQLite index is vestigial and container-local) — it works fine on NFS.
- Bad, because single-writer discipline then depends on a `Recreate` deployment strategy, and every byte traverses the LAN twice (NAS→node→client).
- Bad, because it re-entangles a NAS-resident dataset with cluster lifecycle — the exact lesson ADR-0004 retired.

### olah as TrueNAS catalog/custom app

- Good, because byte-level behavior is identical to the chosen option and the NAS UI manages the container.
- Bad, because it sits outside the doco-cd GitOps lane; there is no catalog entry, and the vendor compose example ships the stale typo tag — custom-app YAML would be hand-tended.

### hugrs (Rust HF mirror)

- Good, because its content-addressed 4 MiB chunks give cross-file dedup and compression — genuinely nicer disk economics for multi-revision hoarding.
- Neutral, because an S3 (MinIO) backend is available, but a MinIO endpoint on the same HDD pool adds a per-object tax on ~50,000 chunk GETs per big model — strictly slower on this hardware.
- Bad, because it is 5 stars / single-maintainer, its SQLite index runs in WAL mode (unusable on network filesystems, forcing local-disk metadata), and its behavior for Xet-backed repos with `hf_xet` clients is unverified.

### kkRepo huggingface-proxy repository type

- Good, because it is a Nexus-class artifact manager: ACLs, S3-compatible blob store, cleanup policies, documented three-way integrity verification, and first-class gated support.
- Neutral, because it is a Java service — fine for a homelab, heavier than a single Python container, and doubles as a Docker/PyPI/npm proxy if ever wanted.
- Bad, because the HF proxy covers models only (no datasets/spaces), and gated access needs one upstream bearer token stored server-side at rest — versusolah holding no credentials at all.

### Dragonfly (d7y.io) with hf:// backend

- Good, because it is CNCF-graduated, the `hf://` backend is real (models/datasets/Spaces, revision pinning, gated tokens), and it also accelerates OCI image distribution with cross-registry blob dedup.
- Neutral, because at two inference systems on a LAN the P2P fan-out benefit is negligible.
- Bad, because it cannot serve native HF clients: access requires explicit `dfget` calls, output is not the `HF_HOME` cache format (invisible to `HF_HUB_OFFLINE`), and `hf://` is not wired into preheat — no warm without a pod.
- Bad, because seed-peer retention is TTL-only with no pinning, the client is a weekly-churning Rust project with thin HF docs, and at evaluation time the client's origin HTTPS used a no-verify TLS mode.

### zot/Harbor OCI route

- Good, because OCI artifacts plus registry digests and later cosign/notation signing give the strongest immutability and provenance story — the right store of record for production-served models.
- Bad, because huggingface.co does not speak the OCI distribution API, so zot cannot pull-through HF at all; every model revision must be re-packaged (modctl/KitOps/AIKit), which inverts the "experiments just work" requirement.

### Warmer Job only + HF_HUB_OFFLINE

- Good, because it is near-zero components (one CronJob warming a shared PVC; the llm-d / vLLM production-stack pattern) and fully GitOps via Flux.
- Bad, because an un-prefetched model is a hard failure, not an on-demand fetch — it rejects the very ergonomics this decision is about. Retained as a complement for offline-pinned serving, not as the cache.

## More Information

-olah (pinned v0.5.1): <https://github.com/vtuber-plan/olah>

- doco-cd: <https://github.com/kimdre/doco-cd>
- ADR-0004 (TrueNAS + doco-cd boundary this ADR extends)
- Xet/CAS protocol background and `HF_ENDPOINT` scope: <https://huggingface.co/docs/huggingface_hub/en/guides/manage-cache>, <https://huggingface.co/docs/hub/en/xet/using-xet-storage>
