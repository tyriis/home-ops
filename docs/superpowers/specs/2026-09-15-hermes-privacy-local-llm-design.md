# Hermes Full Privacy — Local LLM Only via techtales Gateway

- **Date:** 2026-09-15
- **Status:** Approved design (pending implementation plan)
- **App:** `kubernetes/main/apps/hermes-agent`
- **Scope decision:** Models only — provider cleanup, no NetworkPolicy lockdown in this ticket.

## Problem

The hermes-agent gateway and webui currently send LLM traffic to third-party
internet providers, not just our own infrastructure:

1. `fallback_providers` routes to `opencode-go` (`glm-5.3-flash`) and
   `opencode-zen` (`big-pickle`). Any hiccup with the primary provider
   silently leaks prompts to `opencode.ai`.
2. Five auxiliary tasks (`approval`, `mcp`, `triage_specifier`,
   `profile_describer`, `session_search`) use `provider: auto`, which can
   resolve to any configured provider — including the fallback routes above.
3. Unused credentials for the third-party providers are mounted into both
   containers (`OPENCODE_GO_API_KEY`, `OPENCODE_ZEN_API_KEY`).

## Goal

All model inference in hermes flows exclusively through the self-hosted
`techtales` gateway:

- `base_url: https://techtales.ai/v1` (new-api/bifrost gateway, LAN
  `192.168.100.10:443` — already allowed by the existing NetworkPolicy).
- Model: `qwen3.8-flash-next` (existing default, served via our own
  gateway/ollama stack).
- No other provider or fallback route remains configured. No prompt can
  ever leave via a model API other than techtales.

## Non-Goals (explicit, potential follow-up ticket)

- NetworkPolicy changes: the broad internet-egress rule stays as-is
  ("models only" scope decision).
- Non-model external services stay unchanged:
  - TTS via `edge` (Microsoft online voices)
  - Image generation via `fal-ai` (FAL_KEY stays)
  - `x_search` (grok model reference)
  - Model catalog fetch from `hermes-agent.nousresearch.com`
  - firecrawl web search/extract (already in-cluster; scraping the web is
    its function)
- No changes to entity/model ids, STT (already local), or the webui itself.

## Design

Config-only, GitOps-first. Two files change in
`kubernetes/main/apps/hermes-agent/app/`:

### 1. `configmap.yaml`

- **Remove `providers.opencode-go`** entirely (the model allowlist block
  added as a webui picker override). `providers:` retains only
  `techtales`. The webui picker continues to be driven by
  `custom_providers.techtales.models:` (kept as-is).
- **Empty `fallback_providers`** → `fallback_providers: []`, removing the
  `opencode-go` and `opencode-zen` entries. This is the core privacy fix.
- **Pin auxiliary `provider: auto` → `provider: techtales`** for:
  `approval`, `mcp`, `triage_specifier`, `profile_describer`,
  `session_search`. Their `model:`/`base_url:`/`api_key:` fields stay empty
  (inherit provider default), matching the other auxiliary entries that
  already pin `techtales`.

Note: `config.yaml` is rendered from the ConfigMap and re-copied to
`/opt/data/config.yaml` by the `init-config` initContainer on every pod
start, so the ConfigMap is the source of truth — no in-cluster manual
edits.

### 2. `external-secret.yaml`

- Remove `OPENCODE_GO_API_KEY` and `OPENCODE_ZEN_API_KEY` from the
  `ExternalSecret` target template so those credentials are no longer
  mounted. The backing values remain in OpenBao (optional later purge,
  out of scope).

### 3. Commit hygiene

- `FIRECRAWL_API_URL` line keeps its existing `#NOSONAR` annotation.
- Both containers share `${APP}-secret` via `envFrom`; removing template
  keys requires a pod restart — handled automatically by
  `reloader.stakater.com/auto` on ConfigMap/Secret change.

## Rollout

1. Commit both manifest changes to `main`; Flux reconciles
   `HelmRelease/hermes-agent` (interval 30m, `reloader` reacts to the
   ConfigMap and Secret refresh, `Recreate` strategy).
2. Init container overwrites `/opt/data/config.yaml` with the new render.

## Verification

- `kubectl -n hermes-agent get pods` — pods recreate and become Ready
  (webui `/health` probe).
- In the webui (`<agent>.techtales.io`): chat round-trip succeeds; model
  picker shows only the `techtales` model list.
- On the bifrost/new-api gateway: the chat request appears in gateway
  logs for `qwen3.8-flash-next`.
- Privacy evidence from inside the app pod: no DNS resolution/connections
  to `opencode.ai` (e.g., resolve attempt fails via config absence; no
  gateway-side hits on opencode).
- Negative check: force a primary-provider failure (if practical) — no
  request should land on any non-techtales endpoint, since
  `fallback_providers` is now empty.

## Risks / Tradeoffs

- **No fallback:** if the techtales gateway or local model stack is down,
  hermes has degraded chat until it recovers. Accepted — that is the
  point of the ticket.
- **Auxiliary latency:** auxiliary tasks (compression, titles, etc.) now
  always hit the local gateway instead of possibly faster cloud fallbacks;
  accepted.
- **Webui built-in catalog:** `nesquena/hermes-webui` ships a stale
  built-in `opencode-go` catalog (see #5311 note in the ConfigMap). With
  the provider no longer configured, the picker entry should disappear; if
  the webui still shows it, add a `providers.techtales.models:` allowlist
  override (same mechanism previously used for opencode-go).
