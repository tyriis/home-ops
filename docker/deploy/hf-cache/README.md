# hf-cache

olah — a self-hosted Hugging Face mirror / pull-through cache, running on the TrueNAS box (nas.techtales.io) as a native docker-compose service via doco-cd.
LAN clients set `HF_ENDPOINT` and get byte-cached models, datasets, and Spaces without any HF credential on the NAS.
See ADR 0010 (this service) and ADR 0004 (TrueNAS + doco-cd lane).

## Layout

- `compose.yaml`: shared compose definition (olah CLI flags; no env_file needed)
- `docker/truenas/hf-cache/compose.yaml`: truenas target instance
- `docker/truenas/hf-cache/.env`: target identifier + host cache dataset path
- `docker/.doco-cd.truenas.yaml`: doco-cd registration for the truenas target

The target host was identified as `truenas` from `docker/.doco-cd.truenas.yaml` and `docker/deploy/minio/truenas.env` (`/mnt/tank/...` pool paths); `synology` is the old NAS (`/volume1/...`), `red` is the RTX 2060 GPU box.

## Secrets

None. olah holds no HF token — gated downloads use client-token pass-through and the visibility cache is per-token, fail-closed. There is therefore no `sops.env` for this service.

## Ports

- `8090`: olah (plain HTTP) — bound on all interfaces; TLS terminates at Nginx Proxy Manager.

## Manual provisioning (one-time, NAS-side)

1. Create the cache dataset (set `recordsize` BEFORE first writes):

   ```bash
   zfs create -o recordsize=1M -o atime=off tank/apps/hf-cache
   zfs set quota=10T tank/apps/hf-cache
   ```

   olah mounts it at `/mnt/tank/apps/hf-cache` → container `/data/repos`, and its own `cache-size-limit` (8TB) stays below the 10T ZFS quota.

2. In Nginx Proxy Manager, add a proxy host `hf.techtales.io` → `http://<nas-ip>:8090` with a Let's Encrypt certificate, and on that host's Advanced tab:

   ```nginx
   proxy_buffering off;
   proxy_read_timeout 3600s;
   ```

   `proxy_buffering off` and the extended read timeout are required for multi-GB model streams.

## Client usage

```bash
export HF_ENDPOINT=https://hf.techtales.io
export HF_TOKEN=...            # your own token for gated/licensed models
export HF_HUB_ETAG_TIMEOUT=1800  # optional: fewer metadata revalidations
```

License acceptance for gated models stays tied to the token's HF account. `transformers`, vLLM, TEI and the `hf` CLI all work with just `HF_ENDPOINT`.

## Notes

- Exactly one olah instance — it refuses multiple writers over one cache dataset.
- The app's `~/.olah` dir is container-local and disposable; nothing there needs persisting. Only `/data/repos` is a bind mount.
- v0.x upgrades may require wiping the cache dataset between versions (upstream: cached data is not migratable).
  Pin bumps ride the existing `docker/` Renovate flow — test before promoting, then `rm -rf /mnt/tank/apps/hf-cache/*` if the app reports CRC/format mismatches after a version change.
- The upstream compose example references the stale typo tag `lastet`; this repo pins `xiahan2019/olah:0.5.1@sha256:...` instead.
- Acceptance test: `HF_ENDPOINT=https://hf.techtales.io hf download <public repo>` twice — the second run must complete at LAN speed with zero NAS egress.
