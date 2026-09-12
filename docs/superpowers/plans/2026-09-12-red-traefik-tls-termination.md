# red Traefik TLS Termination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Terminate TLS for red's `unsloth`, `comfyui`, `gallery`, and `ollama` services with a Traefik instance on `tyriis.dev`, without touching the working bifrost Traefik.

**Architecture:** A red host shim `include`s the shared `docker/deploy/traefik/compose.yaml` and overrides only `command:` (compose replaces list fields, so bifrost's techtales domains are not inherited). Per-service red shims attach workloads to the host-local `apps` bridge network, add Traefik Docker labels, and bind their published ports to loopback. doco-cd discovers red's workloads via `docker/.doco-cd.red.yaml`.

**Tech Stack:** Docker Compose (v2/v5), Traefik v3.7.13, Cloudflare DNS-01 / Let's Encrypt, SOPS (age), doco-cd.

**Reference files (read before starting):**
- `docker/deploy/traefik/compose.yaml` — shared Traefik definition (do not modify).
- `docker/bifrost/traefik/compose.yaml` + `docker/bifrost/new-api/compose.yaml` — shim/label patterns.
- `docker/red/unsloth/compose.yaml`, `docker/red/arcane-agent/compose.yaml` — existing red shims.
- `docs/superpowers/specs/2026-09-12-red-traefik-tls-termination-design.md` — the spec this plan implements.

**Notes for the implementer:** You are authorized and expected to add/adjust comments, formatting, and lint/CI suppressions required to pass `pre-commit`, `yamllint`, and `prettier`. Do **not** modify `docker/deploy/traefik/compose.yaml`, anything under `docker/bifrost/**`, or the metrics services' networking. Do not commit real secrets. Do not commit or push unless the task says to.

---

## File Structure

| File | Action | Responsibility |
| --- | --- | --- |
| `docker/red/traefik/compose.yaml` | Create | Traefik shim + red `command:` override (`tyriis.dev` wildcard) |
| `docker/red/traefik/.env` | Create | `TARGET`, `TLS_DOMAIN`, `ACME_EMAIL` |
| `docker/red/traefik/sops.env` | Create (SOPS) | Encrypted `CF_DNS_API_TOKEN` placeholder |
| `docker/red/unsloth/compose.yaml` | Modify | `apps` + labels + loopback ports |
| `docker/red/ollama/compose.yaml` | Create | `apps` + labels + loopback port |
| `docker/red/comfyui/compose.yaml` | Create | `apps` + labels + loopback ports (both UIs) |
| `docker/.doco-cd.red.yaml` | Modify | Add `traefik`; repoint `ollama`/`comfyui` |
| `docker/deploy/node-exporter/compose.yaml` | Modify | smartctl-exporter image pin |
| `docker/red/README.md` | Create | Host doc: routing, DNS, first-deploy |

**Shared shim boilerplate** (used verbatim in the new shim files below; adjust only the shared-compose path):

```yaml
---
# Include shim — the actual service definition is shared: docker/deploy/<SVC>/compose.yaml.
# doco-cd runs compose in working_dir and hard-fails ("no compose files found") unless a
# compose file is resolvable there; this real file provides it. Symlinks are deliberately
# avoided (redeploy-hash churn, doco-cd #954; path-escape false positives, v0.74
# regressions #1142/#1086/#1152).
# project_directory: . is REQUIRED so relative paths inside the shared compose
# (env_file, volumes) resolve against this host directory, not the deploy dir.
```

---

### Task 1: red Traefik instance

**Files:**
- Create: `docker/red/traefik/compose.yaml`
- Create: `docker/red/traefik/.env`
- Create: `docker/red/traefik/sops.env`

- [ ] **Step 1: Create the Traefik shim**

Create `docker/red/traefik/compose.yaml`:

```yaml
---
# Include shim — the service definition is shared: docker/deploy/traefik/compose.yaml.
# doco-cd runs compose in working_dir and hard-fails ("no compose files found") unless a
# compose file is resolvable there; this real file provides it. Symlinks are deliberately
# avoided (redeploy-hash churn, doco-cd #954; path-escape false positives, v0.74
# regressions #1142/#1086/#1152).
# project_directory: . is REQUIRED so relative paths inside the shared compose
# (env_file, the /certs volume) resolve against this host directory, not the deploy dir.
#
# `command:` is overridden in full because compose replaces list fields from an include
# instead of appending. This lets red serve the tyriis.dev wildcard while the shared
# definition (image, apps network, ports, env_file, security options) stays untouched for
# bifrost.
include:
  - path: ../../deploy/traefik/compose.yaml
    project_directory: .

services:
  traefik:
    command:
      # Let's Encrypt registration email — REQUIRED, from docker/red/traefik/.env.
      - --certificatesresolvers.cf.acme.email=${ACME_EMAIL:?set ACME_EMAIL in the stack .env}
      - --certificatesresolvers.cf.acme.caserver=https://acme-v02.api.letsencrypt.org/directory
      # Cloudflare DNS challenge
      - --certificatesresolvers.cf.acme.dnschallenge=true
      - --certificatesresolvers.cf.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.cf.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53
      - --certificatesresolvers.cf.acme.storage=/certs/acme.json
      # Entry points (global HTTP -> HTTPS redirect)
      - --entryPoints.web.address=:80
      - --entryPoints.web.http.redirections.entryPoint.scheme=https
      - --entryPoints.web.http.redirections.entryPoint.to=websecure
      # HTTPS entry point
      - --entryPoints.websecure.address=:443
      - --entryPoints.websecure.http.tls=true
      - --entryPoints.websecure.http.tls.certResolver=cf
      # Wildcard certificate for this host's domain
      - --entryPoints.websecure.http.tls.domains[0].main=${TLS_DOMAIN:?set TLS_DOMAIN in the stack .env}
      - --entryPoints.websecure.http.tls.domains[0].sans=*.${TLS_DOMAIN}
      # Docker provider
      - --providers.docker=true
      - --providers.docker.exposedByDefault=false
```

- [ ] **Step 2: Create `.env`**

Create `docker/red/traefik/.env`:

```dotenv
TARGET=red
TLS_DOMAIN=tyriis.dev
# Let's Encrypt contact address; change if you prefer a different mailbox.
ACME_EMAIL=admin@tyriis.dev
```

- [ ] **Step 3: Create the SOPS-encrypted token file**

Create the encrypted placeholder (the real token is filled in later by the operator):

```bash
printf 'CF_DNS_API_TOKEN=REPLACE_ME\n' > /tmp/red-traefik-sops.env
mise exec -- sops --encrypt \
  --input-type dotenv --output-type dotenv \
  --filename-override docker/red/traefik/sops.env \
  /tmp/red-traefik-sops.env > docker/red/traefik/sops.env
rm -f /tmp/red-traefik-sops.env
```

- [ ] **Step 4: Verify the encrypted file and shim config**

```bash
grep -c 'sops_lastmodified' docker/red/traefik/sops.env
```
Expected: `1` (and no plaintext `CF_DNS_API_TOKEN=REPLACE_ME` line).

```bash
docker compose --env-file docker/red/traefik/.env -f docker/red/traefik/compose.yaml config | grep -E 'tyriis.dev|techtales'
```
Expected: output contains `tyriis.dev` and `*.tyriis.dev`; contains **no** `techtales`.

```bash
docker compose --env-file docker/red/traefik/.env -f docker/red/traefik/compose.yaml config | grep -E 'container_name|networks|80:80|443:443'
```
Expected: `container_name: traefik`, `apps` network, host port bindings `80`/`443`.

- [ ] **Step 5: Commit**

```bash
git add docker/red/traefik/compose.yaml docker/red/traefik/.env docker/red/traefik/sops.env
git commit -m "feat(traefik): add red tls instance for tyriis.dev"
```

---

### Task 2: Unsloth shim — labels, apps, loopback

**Files:**
- Modify: `docker/red/unsloth/compose.yaml`

- [ ] **Step 1: Rewrite `docker/red/unsloth/compose.yaml`**

```yaml
---
# Include shim — the actual service definition is shared: docker/deploy/unsloth/compose.yaml.
# doco-cd runs compose in working_dir and hard-fails ("no compose files found") unless a
# compose file is resolvable there; this real file provides it. Symlinks are deliberately
# avoided (redeploy-hash churn, doco-cd #954; path-escape false positives, v0.74
# regressions #1142/#1086/#1152).
# project_directory: . is REQUIRED so relative paths inside the shared compose
# (env_file) resolve against this host directory, not the deploy dir.
include:
  - path: ../../deploy/unsloth/compose.yaml
    project_directory: .

networks:
  apps:
    name: apps
    external: false

services:
  unsloth:
    networks:
      - apps
    # Loopback-only: LAN access goes through Traefik TLS (unsloth.tyriis.dev).
    ports: !override
      - "127.0.0.1:8000:8000"
      - "127.0.0.1:8888:8888"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.unsloth.rule=Host(`unsloth.tyriis.dev`)"
      - "traefik.http.routers.unsloth.entrypoints=websecure"
      - "traefik.http.services.unsloth.loadbalancer.server.port=8000"
```

- [ ] **Step 2: Verify config**

```bash
docker compose -f docker/red/unsloth/compose.yaml config | grep -E 'unsloth.tyriis.dev|127.0.0.1:8000|127.0.0.1:8888|apps'
```
Expected: the host rule, both loopback bindings, and `apps` network all present.

- [ ] **Step 3: Commit**

```bash
git add docker/red/unsloth/compose.yaml
git commit -m "feat(unsloth): front red studio with traefik tls"
```

---

### Task 3: Ollama shim

**Files:**
- Create: `docker/red/ollama/compose.yaml`

- [ ] **Step 1: Create `docker/red/ollama/compose.yaml`**

```yaml
---
# Include shim — the actual service definition is shared: docker/deploy/ollama/compose.yaml.
# doco-cd runs compose in working_dir and hard-fails ("no compose files found") unless a
# compose file is resolvable there; this real file provides it. Symlinks are deliberately
# avoided (redeploy-hash churn, doco-cd #954; path-escape false positives, v0.74
# regressions #1142/#1086/#1152).
# project_directory: . is REQUIRED so relative paths inside the shared compose
# (volumes) resolve against this host directory, not the deploy dir.
include:
  - path: ../../deploy/ollama/compose.yaml
    project_directory: .

networks:
  apps:
    name: apps
    external: false

services:
  ollama:
    networks:
      - apps
    # Loopback-only: LAN access goes through Traefik TLS (ollama.tyriis.dev).
    ports: !override
      - "127.0.0.1:11434:11434"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(`ollama.tyriis.dev`)"
      - "traefik.http.routers.ollama.entrypoints=websecure"
      - "traefik.http.services.ollama.loadbalancer.server.port=11434"
```

- [ ] **Step 2: Verify config**

```bash
docker compose -f docker/red/ollama/compose.yaml config | grep -E 'ollama.tyriis.dev|127.0.0.1:11434|apps'
```
Expected: host rule, loopback binding, `apps` network present.

- [ ] **Step 3: Commit**

```bash
git add docker/red/ollama/compose.yaml
git commit -m "feat(ollama): front red api with traefik tls"
```

---

### Task 4: ComfyUI shim (both web UIs)

**Files:**
- Create: `docker/red/comfyui/compose.yaml`

- [ ] **Step 1: Create `docker/red/comfyui/compose.yaml`**

```yaml
---
# Include shim — the actual service definition is shared: docker/deploy/comfyui/compose.yaml.
# doco-cd runs compose in working_dir and hard-fails ("no compose files found") unless a
# compose file is resolvable there; this real file provides it. Symlinks are deliberately
# avoided (redeploy-hash churn, doco-cd #954; path-escape false positives, v0.74
# regressions #1142/#1086/#1152).
# project_directory: . is REQUIRED so relative paths inside the shared compose
# (volumes) resolve against this host directory, not the deploy dir.
include:
  - path: ../../deploy/comfyui/compose.yaml
    project_directory: .

networks:
  apps:
    name: apps
    external: false

services:
  comfyui-nvidia:
    networks:
      - apps
    # Loopback-only: LAN access goes through Traefik TLS (comfyui.tyriis.dev).
    ports: !override
      - "127.0.0.1:8188:8188"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.comfyui.rule=Host(`comfyui.tyriis.dev`)"
      - "traefik.http.routers.comfyui.entrypoints=websecure"
      - "traefik.http.services.comfyui.loadbalancer.server.port=8188"

  comfyui-gallery:
    networks:
      - apps
    # Loopback-only: LAN access goes through Traefik TLS (gallery.tyriis.dev).
    ports: !override
      - "127.0.0.1:8189:8189"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.gallery.rule=Host(`gallery.tyriis.dev`)"
      - "traefik.http.routers.gallery.entrypoints=websecure"
      - "traefik.http.services.gallery.loadbalancer.server.port=8189"
```

- [ ] **Step 2: Verify config**

```bash
docker compose -f docker/red/comfyui/compose.yaml config | grep -E 'comfyui.tyriis.dev|gallery.tyriis.dev|127.0.0.1:818[89]|apps'
```
Expected: both host rules, both loopback bindings, `apps` network present. Also confirm `fix-permissions` is still present:

```bash
docker compose -f docker/red/comfyui/compose.yaml config --services
```
Expected: `comfyui-nvidia`, `comfyui-gallery`, `fix-permissions`.

- [ ] **Step 3: Commit**

```bash
git add docker/red/comfyui/compose.yaml
git commit -m "feat(comfyui): front red uis with traefik tls"
```

---

### Task 5: doco-cd red workload list

**Files:**
- Modify: `docker/.doco-cd.red.yaml`

- [ ] **Step 1: Update `docker/.doco-cd.red.yaml`**

Replace the whole file with:

```yaml
# ---
# this does not work when updated :(
# name: doco-cd
# working_dir: docker/deploy/doco-cd
# env_files:
#   - red.env
---
# Traefik first: it creates the shared `apps` network and the TLS entry points before
# the labelled services attach.
name: traefik
working_dir: docker/red/traefik
env_files:
  - .env
---
name: busybox-enc
working_dir: docker/red/busybox-enc
env_files:
  - .env
---
name: ollama
working_dir: docker/red/ollama
---
name: node-exporter
working_dir: docker/deploy/node-exporter
---
name: comfyui
working_dir: docker/red/comfyui
---
name: unsloth
working_dir: docker/red/unsloth
env_files:
  - .env
---
name: arcane-agent
working_dir: docker/red/arcane-agent
env_files:
  - .env
```

- [ ] **Step 2: Verify YAML and working dirs**

```bash
python3 -c "import yaml,sys; docs=list(yaml.safe_load_all(open('docker/.doco-cd.red.yaml'))); print([d['name'] for d in docs if d])"
```
Expected: `['traefik', 'busybox-enc', 'ollama', 'node-exporter', 'comfyui', 'unsloth', 'arcane-agent']` (`traefik` first).

```bash
for d in docker/red/traefik docker/red/ollama docker/red/comfyui docker/red/unsloth; do test -f "$d/compose.yaml" && echo "OK $d" || echo "MISSING $d"; done
```
Expected: four `OK` lines.

- [ ] **Step 3: Commit**

```bash
git add docker/.doco-cd.red.yaml
git commit -m "feat(doco-cd): route red services through traefik"
```

---

### Task 6: smartctl-exporter image pin

**Files:**
- Modify: `docker/deploy/node-exporter/compose.yaml:28`

- [ ] **Step 1: Change the image**

Replace the `image:` line of the `smartctl-exporter` service with:

```yaml
    image: ghcr.io/prometheus-community/smartctl-exporter:master@sha256:7a0f8712313bbf38f2534d57fb256dde97c6fb3d9a16323c4f933cca8e10b49c
```

- [ ] **Step 2: Verify config and that no other line changed**

```bash
docker compose -f docker/deploy/node-exporter/compose.yaml config >/dev/null && echo OK
git diff -- docker/deploy/node-exporter/compose.yaml
```
Expected: `OK`, and the diff shows exactly one changed `image:` line.

- [ ] **Step 3: Commit**

```bash
git add docker/deploy/node-exporter/compose.yaml
git commit -m "fix(node-exporter): pin smartctl exporter image"
```

---

### Task 7: red host README

**Files:**
- Create: `docker/red/README.md`

- [ ] **Step 1: Create `docker/red/README.md`**

```markdown
# red

LAN-only Docker host: GPU workstation (`192.168.1.22`, NVIDIA RTX 2060 Super 8 GB) running local
LLM/image tooling and an Arcane edge agent. GitOps via doco-cd with `TARGET=red`
(`docker/.doco-cd.red.yaml`).

## Services

| Service                  | Hostname                  | Backend (container port)      | Direct host port    |
| ------------------------ | ------------------------- | ----------------------------- | ------------------- |
| traefik                  | —                         | —                             | `80`/`443` (LAN)    |
| unsloth (Studio UI/API)  | `unsloth.tyriis.dev`      | `unsloth:8000`                | `127.0.0.1:8000`    |
| unsloth Jupyter          | internal                  | `unsloth:8888`                | `127.0.0.1:8888`    |
| comfyui                  | `comfyui.tyriis.dev`      | `comfyui-nvidia:8188`         | `127.0.0.1:8188`    |
| comfyui-gallery          | `gallery.tyriis.dev`      | `comfyui-gallery:8189`        | `127.0.0.1:8189`    |
| ollama                   | `ollama.tyriis.dev`       | `ollama:11434`                | `127.0.0.1:11434`   |
| node-exporter            | not proxied               | host net `:9100`              | `:9100`             |
| smartctl-exporter        | not proxied               | `:9633`                       | `:9633`             |
| busybox-enc              | —                         | SOPS decrypt smoke test       | —                   |
| arcane-agent             | —                         | outbound edge poll to bifrost | —                   |

Traefik terminates TLS for the four proxied services and redirects HTTP to HTTPS. It obtains a
single wildcard certificate (`tyriis.dev` + `*.tyriis.dev`) from Let's Encrypt via the Cloudflare
DNS-01 challenge. The shared Traefik definition lives in `docker/deploy/traefik/compose.yaml`; the
red instance is an include shim that overrides only the static `command:` (see
`docker/red/traefik/compose.yaml`).

**Metrics are intentionally not proxied.** `node-exporter` needs `network_mode: host` for correct
`netdev`/`netstat`/`sockstat` metrics (`/proc/net` is netns-scoped), so it and `smartctl-exporter`
are scraped directly on the LAN.

## First deploy

1. Create UniFi (UDM SE) local DNS A records → `192.168.1.22` for `unsloth`, `comfyui`,
   `gallery`, `ollama` `.tyriis.dev`.
2. Put the real Cloudflare token (Zone:DNS:Edit on the `tyriis.dev` zone) into the encrypted
   file: `sops docker/red/traefik/sops.env`, replace `CF_DNS_API_TOKEN=REPLACE_ME`.
3. Confirm `ACME_EMAIL` in `docker/red/traefik/.env`.
4. Ensure red's doco-cd has the red age key (`SOPS_AGE_KEY_FILE`) so `sops.env` decrypts.
5. Let doco-cd apply `docker/.doco-cd.red.yaml` (Traefik first).

Verify: `curl -sI https://unsloth.tyriis.dev` serves a valid `*.tyriis.dev` certificate, HTTP
redirects to HTTPS, and the loopback ports are unreachable from another LAN host.

## Notes

- TLS provides transport security, not authentication. `ollama`, `comfyui`, and `gallery` have no
  login of their own; they are LAN-only via private-IP DNS. Do not port-forward them.
- Per-service layout follows the bifrost pattern: a real thin `compose.yaml` include shim plus the
  host's `.env`/`sops.env`. Symlinks are avoided (doco-cd redeploy-hash churn and path-escape
  false positives).
```

- [ ] **Step 2: Verify markdown lint**

```bash
pre-commit run markdownlint-fix --files docker/red/README.md
```
Expected: passes (or auto-fixes and re-run clean).

- [ ] **Step 3: Commit**

```bash
git add docker/red/README.md
git commit -m "docs(red): document traefik tls layout"
```

---

### Task 8: Final validation

- [ ] **Step 1: Confirm the shared Traefik definition and bifrost are untouched**

```bash
git diff --exit-code origin/main -- docker/deploy/traefik/compose.yaml docker/bifrost/
```
Expected: exit `0`, no output.

- [ ] **Step 2: Validate every red shim**

```bash
docker compose --env-file docker/red/traefik/.env -f docker/red/traefik/compose.yaml config >/dev/null && \
docker compose -f docker/red/unsloth/compose.yaml config >/dev/null && \
docker compose -f docker/red/ollama/compose.yaml config >/dev/null && \
docker compose -f docker/red/comfyui/compose.yaml config >/dev/null && echo ALL_OK
```
Expected: `ALL_OK`.

- [ ] **Step 3: Run pre-commit on all changed files**

```bash
pre-commit run --files \
  docker/red/traefik/compose.yaml docker/red/traefik/.env docker/red/traefik/sops.env \
  docker/red/unsloth/compose.yaml docker/red/ollama/compose.yaml docker/red/comfyui/compose.yaml \
  docker/.doco-cd.red.yaml docker/deploy/node-exporter/compose.yaml docker/red/README.md
```
Expected: all hooks pass (fix any auto-fixable findings and re-run).

- [ ] **Step 4: Confirm no symlinks remain under `docker/red`**

```bash
find docker/red -type l
```
Expected: no output.

---

## Self-Review

**Spec coverage:** D1 → Task 1; D2 → Task 1 (domains in `command:`); D3 → Tasks 2–4 (`apps` + labels); D4 → Tasks 2–4 (loopback ports); D5 → Task 6; doco-cd → Task 5; documentation → Task 7; verification → Task 8. Metrics non-goal honored (no changes to `node-exporter` networking). Manual prerequisites are in Task 7's README and the spec.

**Placeholder scan:** only the intentional `CF_DNS_API_TOKEN=REPLACE_ME` placeholder inside the SOPS-encrypted file, which the operator replaces (documented). No TBDs.

**Type/name consistency:** router/service names (`unsloth`, `comfyui`, `gallery`, `ollama`) and container ports (`8000`, `8188`, `8189`, `11434`) match the spec's routing table and the shared composes' service names (`unsloth`, `ollama`, `comfyui-nvidia`, `comfyui-gallery`).
