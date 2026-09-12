# red Traefik TLS termination (`tyriis.dev`) — Design

- **Status:** Accepted
- **Date:** 2026-09-12
- **Scope:** `docker/red/**`, `docker/deploy/node-exporter/compose.yaml`, `docker/.doco-cd.red.yaml`
- **Supersedes:** the "Reverse proxy or TLS termination" non-goal in `docs/superpowers/specs/2026-08-16-unsloth-doco-cd-design.md`

## Context

`red` is a LAN-only Docker host (workstation, `192.168.1.22`, NVIDIA RTX 2060 Super 8 GB) deployed
via `doco-cd` with `TARGET=red`. Today its workloads are plaintext on the LAN:

| Workload | Direct port | Source |
| --- | --- | --- |
| `unsloth` (Studio UI/API) | `8000` all interfaces | `docker/deploy/unsloth/compose.yaml` (shim `docker/red/unsloth/`) |
| `unsloth` Jupyter | `127.0.0.1:8888` | same |
| `comfyui-nvidia` | `8188` all interfaces | `docker/deploy/comfyui/compose.yaml` |
| `comfyui-gallery` | `8189` all interfaces | same |
| `ollama` | `11434` all interfaces | `docker/deploy/ollama/compose.yaml` |
| `node-exporter` | host net `9100` (shared with purple/bifrost) | `docker/deploy/node-exporter/compose.yaml` |
| `smartctl-exporter` | `9633` | same |
| `arcane-agent` | outbound only (edge poll to bifrost Manager) | `docker/red/arcane-agent/` |

`bifrost` already runs Traefik with Cloudflare DNS-01 Let's Encrypt certificates for
`*.techtales.ai` (see `docker/deploy/traefik/compose.yaml`, `docker/bifrost/README.md`). `red`
should get the same treatment for the domain `tyriis.dev`.

## Goals

- TLS termination (Let's Encrypt, HTTP→HTTPS redirect) in front of red's browser/HTTP workloads:
  `unsloth`, `comfyui`, `gallery`, `ollama`.
- Hostnames under `tyriis.dev`, one wildcard certificate.
- Reuse the existing shared Traefik definition without changing the working `bifrost` instance.
- Follow the established `docker/deploy/<svc>` shared-compose + per-host include-shim convention.
- Restrict direct plaintext host ports of the now-proxied services to loopback.

## Non-goals

- **Metrics are out of scope.** `node-exporter` and `smartctl-exporter` are *not* routed through
  Traefik and keep their current networking/binding. `network_mode: host` on `node-exporter` is
  load-bearing: `/proc/net` resolves against the reader's netns, so moving it to a bridge silently
  breaks `netdev`/`netstat`/`sockstat`/`arp`/`conntrack` (see `prometheus/node_exporter` #2007,
  #3381). It stays as-is.
- No authentication/authorization middleware. Traefik provides TLS, not auth.
- No public exposure (LAN-only, private-IP DNS records).
- No changes to `docker/deploy/traefik/compose.yaml` (bifrost-safe).
- Jupyter (`:8888`) stays internal (loopback only), not published.

## Decisions

### D1 — Red-specific static config via shim `command:` override

`docker/red/traefik/compose.yaml` is a real include shim over `docker/deploy/traefik/compose.yaml`
that overrides **only** `services.traefik.command` with red's static configuration (wildcard domains
for `tyriis.dev`). Verified with `docker compose config`: a list field set in the including file
replaces the included list wholesale. `image`, volumes, `apps` network, ports, `env_file`, and
security options are inherited.

Rationale: red needs a *different* domain set (not a superset), so replacement is exactly right;
the shared file and the live bifrost instance remain untouched. A red-only copy of the whole
compose (rejected) would duplicate ~58 lines and drift. A `${TLS_DOMAIN}` variable in the shared
file (rejected) would touch bifrost.

### D2 — Wildcard certificate

One `certificatesresolvers.cf` (Cloudflare DNS-01, Let's Encrypt production) issues
`tyriis.dev` + `*.tyriis.dev` from the `websecure` entrypoint default TLS domains. All red routers
use `entrypoints=websecure`, so the single wildcard serves them.

### D3 — One `apps` bridge network per host, services reached by Docker labels

Every red workload and Traefik join the host-local `apps` bridge network. Traefik discovers
backends through Docker-provider labels (`traefik.enable`, `traefik.http.routers.*`,
`traefik.http.services.*.loadbalancer.server.port`), exactly as bifrost does. `apps` is
host-local (`name: apps`, `external: false`), so red's is independent of bifrost's.

### D4 — Direct ports restricted to loopback

Proxied services override their published ports to `127.0.0.1` (`!override` on the list). Traefik
reaches containers over `apps`, so host ports are only for local debugging. This applies to
`unsloth` (`8000`, `8888`), `comfyui-nvidia` (`8188`), `comfyui-gallery` (`8189`), `ollama`
(`11434`). Metrics services are excluded (non-goal).

### D5 — smartctl-exporter image change (independent)

`docker/deploy/node-exporter/compose.yaml` switches `smartctl-exporter` to
`ghcr.io/prometheus-community/smartctl-exporter:master@sha256:7a0f8712313bbf38f2534d57fb256dde97c6fb3d9a16323c4f933cca8e10b49c`.
Shared across hosts; behaviour unchanged apart from the image.

## Architecture

```
LAN client ──TLS──> red:443 (Traefik, `apps`)
                      │  Host(...) rules via Docker labels
                      ├── unsloth.tyriis.dev   → unsloth:8000        (apps)
                      ├── comfyui.tyriis.dev   → comfyui-nvidia:8188 (apps)
                      ├── gallery.tyriis.dev   → comfyui-gallery:8189(apps)
                      └── ollama.tyriis.dev    → ollama:11434        (apps)

node-exporter (host net 9100) / smartctl-exporter (9633)  ← unchanged, not proxied
```

### Routing table

| Hostname | Backend (apps) | Container port | Router | Service |
| --- | --- | --- | --- | --- |
| `unsloth.tyriis.dev` | `unsloth` | `8000` | `unsloth` | `unsloth` |
| `comfyui.tyriis.dev` | `comfyui-nvidia` | `8188` | `comfyui` | `comfyui` |
| `gallery.tyriis.dev` | `comfyui-gallery` | `8189` | `gallery` | `gallery` |
| `ollama.tyriis.dev` | `ollama` | `11434` | `ollama` | `ollama` |

Entrypoints: `web` (:80) redirects to `websecure` (:443, TLS default resolver `cf`).

### Traefik binding

Red's Traefik inherits `${WEB_IP:-0.0.0.0}:${HTTP_PORT:-80}` / `${HTTPS_PORT:-443}` from the shared
definition, i.e. it listens on red's LAN interfaces. `ACME_EMAIL` and `TLS_DOMAIN` come from
`docker/red/traefik/.env`; `CF_DNS_API_TOKEN` (Zone:DNS:Edit on the `tyriis.dev` zone) comes from
the SOPS-encrypted `docker/red/traefik/sops.env`, decrypted by doco-cd at deploy time.

## Files

**New**

- `docker/red/traefik/compose.yaml` — include shim + `command:` override (wildcard `tyriis.dev`).
- `docker/red/traefik/.env` — `TARGET=red`, `TLS_DOMAIN=tyriis.dev`, `ACME_EMAIL=…`.
- `docker/red/traefik/sops.env` — SOPS-encrypted `CF_DNS_API_TOKEN` (red age key).
- `docker/red/ollama/compose.yaml` — shim: `apps` + labels + loopback port.
- `docker/red/comfyui/compose.yaml` — shim: `apps` + labels + loopback ports for both web UIs.
- `docker/red/README.md` — host documentation, routing table, DNS runbook, first-deploy notes.

**Modified**

- `docker/red/unsloth/compose.yaml` — add `apps`, labels, loopback ports.
- `docker/.doco-cd.red.yaml` — add `traefik` workload (first), repoint `ollama`/`comfyui` to
  `docker/red/*`; `node-exporter` stays at `docker/deploy/node-exporter`.
- `docker/deploy/node-exporter/compose.yaml` — smartctl-exporter image (D5).

**Unchanged**

- `docker/deploy/traefik/compose.yaml` and everything under `docker/bifrost/**`.

## Manual prerequisites (outside the repo / by operator)

1. UniFi (UDM SE) local DNS A records → `192.168.1.22`: `unsloth`, `comfyui`, `gallery`,
   `ollama`.tyriis.dev.
2. Cloudflare API token scoped **Zone:DNS:Edit** on the `tyriis.dev` zone.
3. Encrypt `docker/red/traefik/sops.env` with the red age recipient
   (`age16pcjw9pvhx2lnx382hrgcpydpjvjz6r8u22wflm228cakedrlgdqzlwx4s`, already covered by
   `.sops.yaml` rule `docker/red/.*/sops\.env$`).
4. Ensure red's doco-cd has the red age key configured (`SOPS_AGE_KEY_FILE`).

## Verification

- `docker compose config` succeeds for `docker/red/traefik`, `docker/red/unsloth`,
  `docker/red/ollama`, `docker/red/comfyui` and shows the expected command, labels, `apps`
  membership, and loopback ports.
- `docker compose config` on `docker/deploy/traefik` is unchanged (no diff).
- `pre-commit run --files <changed files>` passes (yamllint, prettier, check-symlinks, etc.).
- `sops --decrypt docker/red/traefik/sops.env` prints `CF_DNS_API_TOKEN` (operator, with red key).
- Post-deploy (operator): `curl -sI https://unsloth.tyriis.dev` returns a valid LE certificate for
  `*.tyriis.dev`; HTTP redirects to HTTPS; loopback direct ports are not reachable from another
  LAN host.

## Risks

- **First-deploy ordering:** Traefik should be deployed before/with the labelled services so the
  `apps` network and routes exist. `docker/.doco-cd.red.yaml` lists `traefik` first.
- **Certificate issuance** depends on the Cloudflare token covering the `tyriis.dev` zone; a
  wrong/underscoped token fails ACME with DNS-01 errors (same failure mode as bifrost).
- **Bifrost isolation:** because red overrides `command` in its own shim, the shared Traefik
  definition is not modified; a `docker compose config` comparison for
  `docker/deploy/traefik/compose.yaml` guards this.
- **TLS ≠ auth:** `ollama`, `comfyui`, `gallery` have no authentication; they remain LAN-only via
  private-IP DNS.
