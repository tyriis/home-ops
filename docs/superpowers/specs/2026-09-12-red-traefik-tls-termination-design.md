# red Traefik TLS termination (`tyriis.dev`) — Design

- **Status:** Accepted
- **Date:** 2026-09-12
- **Amended:** 2026-09-13 — no proxied service publishes host ports (`ports: !reset []`); Jupyter is
  additionally routed at `jupyter.tyriis.dev` → `unsloth:8888`.
- **Amended:** 2026-09-13 — `ollama.tyriis.dev` now requires an OpenAI-style `Authorization: Bearer`
  key (ADR-0011); the "No authentication/authorization middleware" non-goal is superseded for
  `ollama` only.
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
  `unsloth` (Studio), Jupyter, `comfyui`, `gallery`, `ollama`.
- Hostnames under `tyriis.dev`, one wildcard certificate.
- Reuse the existing shared Traefik definition without changing the working `bifrost` instance.
- Follow the established `docker/deploy/<svc>` shared-compose + per-host include-shim convention.
- Publish no host ports for the proxied services; keep LAN access behind Traefik (TLS).

## Non-goals

- **Metrics are out of scope.** `node-exporter` and `smartctl-exporter` are *not* routed through
  Traefik and keep their current networking/binding. `network_mode: host` on `node-exporter` is
  load-bearing: `/proc/net` resolves against the reader's netns, so moving it to a bridge silently
  breaks `netdev`/`netstat`/`sockstat`/`arp`/`conntrack` (see `prometheus/node_exporter` #2007,
  #3381). It stays as-is.
- No authentication/authorization middleware for `unsloth`, Jupyter, `comfyui`, or `gallery`; Traefik
  provides TLS, not auth, and those services stay LAN-only. `ollama` is the exception: it is gated by
  an OpenAI-style bearer key (ADR-0011).
- No public exposure (LAN-only, private-IP DNS records).
- No changes to `docker/deploy/traefik/compose.yaml` (bifrost-safe).

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

### D4 — Proxied services publish no host ports; Jupyter routed

`docker/red/ollama` (`11434`), `docker/red/unsloth` (Studio `8000`, Jupyter `8888`), and
`docker/red/comfyui` (`comfyui-nvidia` `8188`, `comfyui-gallery` `8189`) all reset their published
ports to none (`ports: !reset []`), dropping the ports inherited from the shared include. Traefik
reaches the containers purely over the `apps` network, so the red host publishes no plaintext ports
for any proxied service. Jupyter is additionally routed at `jupyter.tyriis.dev` → `unsloth:8888`
(router/service `jupyter`), alongside Studio at `unsloth.tyriis.dev` → `unsloth:8000`. Metrics
services are excluded (non-goal).

### D5 — smartctl-exporter image change (independent)

`docker/deploy/node-exporter/compose.yaml` switches `smartctl-exporter` to
`ghcr.io/prometheus-community/smartctl-exporter:master@sha256:7a0f8712313bbf38f2534d57fb256dde97c6fb3d9a16323c4f933cca8e10b49c`.
Shared across hosts; behaviour unchanged apart from the image.

## Architecture

```
LAN client ──TLS──> red:443 (Traefik, `apps`)
                      │  Host(...) rules via Docker labels
                      ├── unsloth.tyriis.dev   → unsloth:8000        (apps)
                      ├── jupyter.tyriis.dev   → unsloth:8888        (apps)
                      ├── comfyui.tyriis.dev   → comfyui-nvidia:8188 (apps)
                      ├── gallery.tyriis.dev   → comfyui-gallery:8189(apps)
                      └── ollama.tyriis.dev    → ollama:11434        (apps)

node-exporter (host net 9100) / smartctl-exporter (9633)  ← unchanged, not proxied
```

### Routing table

| Hostname | Backend (apps) | Container port | Router | Service |
| --- | --- | --- | --- | --- |
| `unsloth.tyriis.dev` | `unsloth` | `8000` | `unsloth` | `unsloth` |
| `jupyter.tyriis.dev` | `unsloth` | `8888` | `jupyter` | `jupyter` |
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
- `docker/red/ollama/compose.yaml` — shim: `apps` + labels + no host ports.
- `docker/red/comfyui/compose.yaml` — shim: `apps` + labels + no host ports.
- `docker/red/README.md` — host documentation, routing table, DNS runbook, first-deploy notes.

**Modified**

- `docker/red/unsloth/compose.yaml` — add `apps`, labels, the `jupyter` router; reset `ports` to
  none.
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

- `docker compose config` on `docker/red/ollama`, `docker/red/unsloth`, and `docker/red/comfyui`
  emits no `ports` for the services; it shows the expected labels, `apps` membership, and both the
  `unsloth`/`jupyter` and `comfyui`/`gallery` routers/services.
- `docker compose config` on `docker/deploy/traefik` is unchanged (no diff).
- `pre-commit run --files <changed files>` passes (yamllint, prettier, check-symlinks, etc.).
- `sops --decrypt docker/red/traefik/sops.env` prints `CF_DNS_API_TOKEN` (operator, with red key).
- Post-deploy (operator): `curl -sI https://unsloth.tyriis.dev` and
  `https://jupyter.tyriis.dev` return a valid LE certificate for `*.tyriis.dev`; HTTP redirects to
  HTTPS; `https://jupyter.tyriis.dev` loads JupyterLab (kernel/WebSocket works); no host ports are
  published on the LAN.

## Risks

- **First-deploy ordering:** Traefik should be deployed before/with the labelled services so the
  `apps` network and routes exist. `docker/.doco-cd.red.yaml` lists `traefik` first.
- **Certificate issuance** depends on the Cloudflare token covering the `tyriis.dev` zone; a
  wrong/underscoped token fails ACME with DNS-01 errors (same failure mode as bifrost).
- **Bifrost isolation:** because red overrides `command` in its own shim, the shared Traefik
  definition is not modified; a `docker compose config` comparison for
  `docker/deploy/traefik/compose.yaml` guards this.
- **TLS ≠ auth:** `comfyui` and `gallery` have no authentication; they remain LAN-only via
  private-IP DNS. `ollama` is gated by an OpenAI-style bearer key (ADR-0011), so requests without it
  return `401`.
- **Jupyter Host/remote access:** the May image's entrypoint came from a now-private repo, so its
  default Jupyter config is not fully auditable. If Jupyter rejects the proxied `Host` header
  (`jupyter.tyriis.dev`), the fallback is to mount a `jupyter_lab_config.py` setting
  `allow_remote_access`/`local_hostnames`.
