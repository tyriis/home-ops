# red

LAN-only Docker host: GPU workstation (`192.168.1.22`, NVIDIA RTX 2060 Super 8 GB) running local
LLM/image tooling and an Arcane edge agent. GitOps via doco-cd with `TARGET=red`
(`docker/.doco-cd.red.yaml`).

## Services

| Service                 | Hostname             | Backend (container port)            | Direct host port |
| ----------------------- | -------------------- | ----------------------------------- | ---------------- |
| traefik                 | —                    | —                                   | `80`/`443` (LAN) |
| unsloth (Studio UI/API) | `unsloth.tyriis.dev` | `unsloth:8000`                      | —                |
| unsloth Jupyter         | `jupyter.tyriis.dev` | `unsloth:8888`                      | —                |
| comfyui                 | `comfyui.tyriis.dev` | `comfyui-nvidia:8188`               | —                |
| comfyui-gallery         | `gallery.tyriis.dev` | `comfyui-gallery:8189`              | —                |
| ollama (gated)          | `ollama.tyriis.dev`  | `ollama-auth:8080` → `ollama:11434` | —                |
| node-exporter           | not proxied          | host net `:9100`                    | `:9100`          |
| smartctl-exporter       | not proxied          | `:9633`                             | `:9633`          |
| busybox-enc             | —                    | SOPS decrypt smoke test             | —                |
| arcane-agent            | —                    | outbound edge poll to bifrost       | —                |

Traefik terminates TLS for the five proxied services (Studio, Jupyter, `comfyui`, `gallery`,
`ollama`) and redirects HTTP to HTTPS. It obtains a
single wildcard certificate (`tyriis.dev` + `*.tyriis.dev`) from Let's Encrypt via the Cloudflare
DNS-01 challenge. The shared Traefik definition lives in `docker/deploy/traefik/compose.yaml`; the
red instance is an include shim that overrides only the static `command:` (see
`docker/red/traefik/compose.yaml`).

`ollama.tyriis.dev` is additionally gated by `ollama-auth` — a digest-pinned `caddy:2` container
that requires an OpenAI-style `Authorization: Bearer <key>` header before proxying to
`ollama:11434` (OSS Traefik has no native bearer/API-key middleware). The key exists only in the
SOPS-encrypted `docker/red/ollama/sops.env`; no plaintext key is committed or placed in Compose
labels.

**Metrics are intentionally not proxied.** `node-exporter` needs `network_mode: host` for correct
`netdev`/`netstat`/`sockstat` metrics (`/proc/net` is netns-scoped), so it and `smartctl-exporter`
are scraped directly on the LAN.

## First deploy

1. Create UniFi (UDM SE) local DNS A records → `192.168.1.22` for `unsloth`, `jupyter`, `comfyui`, `gallery`, `ollama` `.tyriis.dev`.
2. Put the real Cloudflare token (Zone:DNS:Edit on the `tyriis.dev` zone) into the encrypted file: `sops docker/red/traefik/sops.env`, replace `CF_DNS_API_TOKEN=REPLACE_ME`.
3. Confirm `ACME_EMAIL` in `docker/red/traefik/.env`.
4. Ensure red's doco-cd has the red age key (`SOPS_AGE_KEY_FILE`) so `sops.env` decrypts.
5. Ensure `docker/red/ollama/sops.env` holds the encrypted `OLLAMA_API_KEY` (committed encrypted;
   rotate with `sops docker/red/ollama/sops.env`).
6. Let doco-cd apply `docker/.doco-cd.red.yaml` (Traefik first).

Verify: `curl -sI https://unsloth.tyriis.dev` serves a valid `*.tyriis.dev` certificate, HTTP
redirects to HTTPS, and no proxied service publishes host ports (Traefik reaches all containers
over the `apps` network). `curl https://ollama.tyriis.dev/api/tags` returns `401` without the key.

## Ollama API key

- Clients must send `Authorization: Bearer <OLLAMA_API_KEY>`:
  - OpenAI-compatible: `base_url=https://ollama.tyriis.dev/v1`, `api_key=<key>`, e.g. `curl https://ollama.tyriis.dev/v1/models -H "Authorization: Bearer $KEY"`.
  - Ollama Python SDK: set `OLLAMA_API_KEY` (sent as a bearer header).
  - Open WebUI: add the connection with `OLLAMA_API_CONFIGS[].key`.
- The official `ollama` CLI has no way to send an arbitrary bearer header; point it at a keyless
  local endpoint instead.
- Rotate: `sops docker/red/ollama/sops.env`, then let doco-cd redeploy the `ollama` stack.

## Notes

- TLS provides transport security. `comfyui` and `gallery` have no login of their own; they are
  LAN-only via private-IP DNS. Do not port-forward them.
- Jupyter is protected by `JUPYTER_PASSWORD`; Studio, `comfyui`, and `gallery` remain
  unauthenticated beyond the LAN boundary.
- Per-service layout follows the bifrost pattern: a real thin `compose.yaml` include shim plus the
  host's `.env`/`sops.env`. Symlinks are avoided (doco-cd redeploy-hash churn and path-escape
  false positives).
- `ollama` auto-pulls the models in `OLLAMA_PULL_MODELS` (compose default `gemma3:1b gemma4:e2b`) on container start; repeat runs are no-ops.
