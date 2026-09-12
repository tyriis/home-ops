---
status: accepted
date: 2026-09-13
decision-makers: [tyriis]
---

# Protect red's Ollama with an OpenAI-style API key

## Context and Problem Statement

`red` (the GPU workstation at `192.168.1.22`) serves Ollama at `https://ollama.tyriis.dev`
through its LAN Traefik instance. The 2026-09-12 TLS design deliberately shipped without
authentication: Traefik terminates TLS, but anything that can reach the LAN can call the API,
consume the GPU, and list/pull models.

Ollama has no built-in API key support; upstream explicitly recommends a reverse proxy for this
(ollama/ollama#8536). Consumers speak the OpenAI contract — the `new-api` gateway on `bifrost`,
OpenAI-compatible clients, and the Ollama Python/JS SDKs all send `Authorization: Bearer <key>`
— so the gate has to accept that scheme. Open-source Traefik v3.7 has no native bearer/API-key
middleware (`apiKey` and `JWT` are Traefik Hub/paid), so the gate must be built from a plugin,
a forward-auth service, or a sidecar proxy.

## Decision Drivers

- Preserve the OpenAI-style `Authorization: Bearer <key>` contract end-to-end.
- Do not execute third-party code inside the TLS terminator (Traefik).
- No runtime dependency on `plugins.traefik.io`: Traefik loads plugins at startup and disables
  plugin-backed middlewares if the download/validation call fails.
- The key must never be committed in plaintext, placed in Compose labels, or visible in
  `docker inspect`.
- Fail closed if the key is unavailable.
- Follow red's existing include-shim + SOPS + per-host `.env`/`sops.env` conventions and keep the
  shared `docker/deploy/ollama` definition host-agnostic.
- Minimal surface: gate only the Ollama route; `comfyui`/`gallery` are unchanged.

## Considered Options

- Caddy sidecar gate (`ollama-auth`) in front of Ollama
- Traefik API-token plugin (`Aetherinox/traefik-api-token-middleware`)
- Traefik API-key plugin (`Septima/traefik-api-key-auth`)
- Traefik ForwardAuth to a small auth service / oauth2-proxy
- nginx sidecar
- Traefik Hub `apiKey` middleware
- Traefik `BasicAuth`
- No change (rely on LAN-only DNS + TLS)

## Decision Outcome

Chosen option: **Caddy sidecar gate (`ollama-auth`)**, because it preserves the OpenAI bearer
contract while keeping all authentication code out of Traefik and avoiding the plugin-download
coupling; Caddy is a stable, digest-pinnable official image and the same pattern already fronts
every other red service.

Concrete parameters:

- `docker/red/ollama/compose.yaml` adds an `ollama-auth` service (`caddy:2.11-alpine`, digest-pinned)
  on the shared `apps` network. It owns the `ollama.tyriis.dev` Traefik router
  (`traefik.http.services.ollama.loadbalancer.server.port=8080`); the `ollama` service keeps no
  Traefik labels and no published host ports.
- `docker/red/ollama/Caddyfile` listens on `:8080` and rejects requests whose `Authorization`
  header is not `Bearer <key>` with `401`, otherwise `reverse_proxy ollama:11434`.
- The key `OLLAMA_API_KEY` is a generated `sk-<64 hex>` value stored SOPS-encrypted in
  `docker/red/ollama/sops.env` (creation rule `docker/red/.*/sops\.env$`, red age key) and injected
  into the container via `env_file: ${SOPS_ENV_FILE:-sops.env}`.
- The Caddyfile uses the `:__unset__` default (`{$OLLAMA_API_KEY:__unset__}`) so the gate fails
  closed if the env var is ever absent.
- The gate is hardened like the rest of the host: `cap_drop: ALL`, `read_only`,
  `no-new-privileges`, tmpfs for `/tmp`, `/config`, `/data`. `NET_BIND_SERVICE` is added back via
  `cap_add` because the official Caddy image ships `/usr/bin/caddy` with the file capability
  `cap_net_bind_service=ep`; with an empty bounding set the kernel refuses to `execve` it
  (`operation not permitted`). The listener is `:8080` (unprivileged), so no other capability is
  needed.

### Consequences

- Good, because the OpenAI-compatible contract is preserved end-to-end; Ollama's own `/v1` API is
  unchanged behind the gate.
- Good, because no third-party module runs in Traefik and there is no `plugins.traefik.io`
  startup dependency.
- Good, because the key stays out of git and out of container labels/`docker inspect`; rotation is
  a single `sops docker/red/ollama/sops.env` edit.
- Good, because it reuses red's established include-shim + SOPS conventions and leaves
  `docker/deploy/ollama/compose.yaml` untouched for other hosts.
- Neutral, because it adds one small container and one proxy hop on the `apps` network.
- Bad, because the official `ollama` CLI cannot send an arbitrary bearer header — CLI use must
  target a keyless local endpoint.
- Bad, because consumers (`new-api`, Open WebUI, SDKs) must each be configured with both the key
  and the TLS URL; the route now returns `401` by default.
- Bad, because the Caddyfile env-var name must stay in sync with `sops.env`.

### Confirmation

- End-to-end against a fake upstream: without a key or with a wrong key → `401`; with the correct
  key → `200` (including `/v1/models`); with `OLLAMA_API_KEY` unset → `401` (fail-closed).
- `caddy validate` / `caddy adapt` on the committed Caddyfile is valid and emits the negated
  `Authorization` matcher plus `reverse_proxy ollama:11434`.
- `docker compose -f docker/red/ollama/compose.yaml config` shows `ollama-auth` carrying the router
  labels, and no labels/ports on `ollama`.
- Post-deploy: `curl https://ollama.tyriis.dev/api/tags` returns `401` without the key; `new-api`
  lists and uses the red models with the key configured.

## Pros and Cons of the Options

### Caddy sidecar gate (ollama-auth)

- Good, because it natively matches `Authorization: Bearer` and is a transparent pass-through for
  Ollama's OpenAI-compatible API.
- Good, because no third-party code executes in Traefik and there is no plugin download step.
- Neutral, because it is one extra small container and one extra hop on the LAN.
- Bad, because the bearer check is a plaintext constant comparison in the dynamic config (the key
  is not hashed), and the Caddyfile must stay consistent with the env var.

### Traefik API-token plugin (Aetherinox/traefik-api-token-middleware)

- Good, because no extra container is needed; it is configured as a Traefik middleware and supports
  `Authorization: Bearer`.
- Neutral, because the token is a plaintext constant and the plugin is small/single-maintainer.
- Bad, because third-party Go code runs inside the TLS terminator and Traefik downloads/validates
  the plugin from `plugins.traefik.io` at every startup, disabling plugin middlewares if that call
  fails (fail-open on route availability).

### Traefik API-key plugin (Septima/traefik-api-key-auth)

- Good, because the shape is identical to the Aetherinox option.
- Bad, because it is stale (last release 2024-06) and carries the same in-process third-party code
  and `plugins.traefik.io` startup coupling.

### Traefik ForwardAuth to a small auth service / oauth2-proxy

- Good, because `ForwardAuth` is a built-in Traefik middleware and centralizes auth decisions.
- Neutral, because a tiny service can validate the `Authorization` header.
- Bad, because it adds and maintains another service; oauth2-proxy is OIDC/browser-oriented and
  overkill for one shared API key.

### nginx sidecar

- Good, because nginx is stable and equivalent to the Caddy gate.
- Neutral, because the footprint is comparable.
- Bad, because the bearer match is more verbose and offers no advantage over Caddy here.

### Traefik Hub apiKey middleware

- Good, because it is first-party and purpose-built, defaulting to `Authorization: Bearer`.
- Bad, because it is a paid/closed product, so it is not viable on an OSS homelab Traefik.

### Traefik BasicAuth

- Good, because it is native and a single middleware.
- Bad, because it is the wrong client contract — OpenAI clients send `Bearer sk-...`, not HTTP
  Basic, so every consumer would have to change.

### No change

- Good, because it is zero work and access is already limited to private-IP DNS + TLS.
- Bad, because TLS is transport security only; anything on the LAN can use the GPU and read/pull
  models — the exact risk recorded in the 2026-09-12 spec.

## More Information

- Supersedes the "No authentication/authorization middleware" non-goal in
  `docs/superpowers/specs/2026-09-12-red-traefik-tls-termination-design.md` (for `ollama` only).
- Ollama has no built-in API key: <https://github.com/ollama/ollama/issues/8536>
- Traefik OSS middleware list: <https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/overview/>
- Traefik Hub `apiKey` (paid): <https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/apikey/>
- Traefik plugin startup coupling: <https://github.com/traefik/traefik/issues/13005>
- Caddy `header`/`not` matchers: <https://caddyserver.com/docs/caddyfile/matchers>
- Ollama OpenAI compatibility: <https://docs.ollama.com/openai-compatibility>
