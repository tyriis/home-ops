# olah

## overview

olah is a self-hosted Hugging Face mirror and pull-through cache. It serves models, datasets, and Spaces transparently — unmodified HF tooling
(`hf` CLI, `huggingface_hub`, `transformers`, vLLM, TEI) reaches it by setting `HF_ENDPOINT` alone. It handles LFS and the Xet delivery protocol
server-side and passes client tokens through for gated repositories, so no HF credential ever rests on the NAS. The rationale and the alternatives
evaluated (hugrs, Dragonfly, zot/Harbor, kkRepo) are recorded in
[ADR-0010](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0010-run-olah-on-truenas-as-the-hugging-face-model-cache.md).

- Endpoint: `https://hf.techtales.io` (TLS terminates at Nginx Proxy Manager on the NAS)
- Source: <https://github.com/vtuber-plan/olah>

## deployment

The first doco-cd component of the NAS system — a native docker-compose service, outside Flux, reconciled by doco-cd from this repository
(see [ADR-0004](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0004-mirgation-from-kubernetes-nas-to-truenas-with-doco-cd.md)):

- Compose definition: `docker/deploy/olah/compose.yaml`
- Host instance: `docker/truenas/olah/` (symlinked compose + `.env`), registered in `docker/.doco-cd.truenas.yaml` as `name: olah`
- Host: `nas.techtales.io`, plain HTTP on port 8090
- Cache dataset: ZFS `tank/olah` (`recordsize=1M`, `atime=off`, quota 5T) mounted at `/data/repos`
- Cache policy: `cache-size-limit=4TB` (stays below the ZFS quota), `LARGE_FIRST` eviction, compression off (ZFS lz4)
- Image: `xiahan2019/olah:0.5.1` digest-pinned; Renovate bumps ride the `docker/` flow

The container is hardened: non-root `3002:3002`, `cap_drop: [ALL]`, `no-new-privileges`, read-only rootfs — the only writable locations are the
cache dataset mount and tmpfs for logs. Single-instance by design: olah refuses multiple writers over one cache dataset.

## client usage

```bash
export HF_ENDPOINT=https://hf.techtales.io
export HF_TOKEN=...                # your own token for gated/licensed models
export HF_HUB_ETAG_TIMEOUT=1800    # optional: fewer metadata revalidations
```

Acceptance test: `hf download <repo>` twice — the second run must complete at LAN speed with zero NAS egress.

## cache management

Eviction is size-driven (hourly janitor at `cache-size-limit`), and there is **no purge API** in olah v0.5.x — targeted deletion is done by
removing directories on the NAS. This is safe while olah is running (reads degrade to a normal cache miss; no restart needed):

```bash
R=/mnt/tank/olah
# fully purge one model repo (repeat models|datasets|spaces as needed):
rm -rf "$R/files/models/<org>/<repo>" "$R/api/models/<org>/<repo>"

# find the biggest cached repos:
du -h --max-depth=3 "$R/files" | sort -h | tail -20
```

Do not delete individual `blocks/*.bin` files or the SQLite state under `~/.olah` (token/log records). The hash-keyed `lfs/` and Xet index trees
are shared across repos — leave them to the janitor. Notes on v0.x upgrades: the on-disk cache format is not migratable between versions, so a
version bump may require wiping the dataset (`rm -rf /mnt/tank/olah/*`).
