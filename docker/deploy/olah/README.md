# olah

olah — a self-hosted Hugging Face mirror / pull-through cache, running on the TrueNAS box (nas.techtales.io) as a native docker-compose service via doco-cd.
LAN clients set `HF_ENDPOINT` and get byte-cached models, datasets, and Spaces without any HF credential on the NAS.
See ADR 0010 (this service) and ADR 0004 (TrueNAS + doco-cd lane).

## Layout

- `docker/deploy/olah/compose.yaml`: shared compose definition (olah CLI flags + security hardening; no env_file needed)
- `docker/truenas/olah/compose.yaml`: symlink to the shared compose (repo convention, same as every other instance)
- `docker/truenas/olah/.env`: target identifier, host cache dataset path, run-as uid/gid
- `docker/.doco-cd.truenas.yaml`: doco-cd registration for the truenas target

## Secrets

None. olah holds no HF token — gated downloads use client-token pass-through and the visibility cache is per-token, fail-closed. There is therefore no `sops.env` for this service.

## Security context

The image runs as root and ships no unprivileged user, so the compose pins the container down instead:

- `user: 3002:3002` — the NAS run-as uid/gid; the cache dataset must be chowned to it (see provisioning below)
- `read_only: true` — the writable set is exactly: the `/data/repos` bind mount, `/tmp` (tmpfs holding the ephemeral logs via `--log-path`),
  and `/data/mirrors` (tmpfs shadowing the image's `VOLUME` declaration so docker injects no anonymous root-owned volume)
- `HOME=/data/repos` — the vestigial `~/.olah` SQLite dir has no path override and must land on a writable path
- `cap_drop: [ALL]` + `no-new-privileges` — olah is pure-Python FastAPI needing no capabilities; 8090 is an unprivileged port

## Ports

- `8090`: olah (plain HTTP) — bound on all interfaces; TLS terminates at Nginx Proxy Manager.

## Manual provisioning (one-time, NAS-side)

### ZFS dataset

Create the cache dataset (set `recordsize` BEFORE first writes) and hand ownership to the container's uid:

```bash
zfs create -o recordsize=1M -o atime=off tank/apps/olah
zfs set quota=10T tank/apps/olah
chown -R 3002:3002 /mnt/tank/apps/olah
```

olah mounts it at `/mnt/tank/apps/olah` → container `/data/repos`, and its own `cache-size-limit` (8TB) stays below the 10T ZFS quota.

### Nginx Proxy Manager

Add a proxy host `hf.techtales.io` → `http://<nas-ip>:8090` with a Let's Encrypt certificate, and on that host's Advanced tab:

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
- The vestigial `~/.olah` dir (HOME=/data/repos, so it lands on the dataset as `.olah`) holds disposable SQLite state; nothing there needs persisting beyond the cache itself.
- v0.x upgrades may require wiping the cache dataset between versions (upstream: cached data is not migratable).
  Pin bumps ride the existing `docker/` Renovate flow — test before promoting, then `rm -rf /mnt/tank/apps/olah/*` if the app reports CRC/format mismatches after a version change.
- The upstream compose example references the stale typo tag `lastet`; this repo pins `xiahan2019/olah:0.5.1@sha256:...` instead.
- Acceptance test: `HF_ENDPOINT=https://hf.techtales.io hf download <public repo>` twice — the second run must complete at LAN speed with zero NAS egress.
