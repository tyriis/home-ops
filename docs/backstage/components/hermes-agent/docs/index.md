# hermes-agent

Hermes Agent gateway + community WebUI frontend. Two containers in one pod, sharing the PVC mounted at `/opt/data`.

## architecture

- `hermes` container: Hermes gateway, `api_server` on `:8642`, runs as uid `10000`, `HERMES_HOME=/opt/data`.
- `webui` container: `ghcr.io/nesquena/hermes-webui` on `:8787`, runs as **root**, `HOME=/opt/data`.
- WebUI chat is gateway-backed: `HERMES_WEBUI_CHAT_BACKEND=gateway` -> `http://localhost:8642`. Auth reuses the shared secret's `API_SERVER_KEY` via `envFrom` fallback (no `HERMES_WEBUI_GATEWAY_API_KEY` set — do not add one).
- `HERMES_WEBUI_GATEWAY_USE_RUNS_API=true` opts the WebUI into the Runs API transport — required for tool-approval cards in the WebUI.

## critical: HERMES_HOME on BOTH containers

Both containers MUST set `HERMES_HOME: /opt/data`. Without it the webui (`HOME=/opt/data`, default profile path
`$HOME/.hermes`) silently creates a shadow profile at `/opt/data/.hermes/` with its own `auth.json`, `config.yaml`
and `state.db`. The webui model picker then reads the shadow `auth.json` while all CLI admin (`hermes auth ...`)
from the gateway side edits `/opt/data/auth.json` — removals and cleanup never take effect, and the shadow dir is
root-owned so the gateway container (uid `10000`) cannot even read it.

Symptom: a removed provider keeps showing in the WebUI model picker.

Check:

```shell
grep -o 'opencode[a-z-]*' /opt/data/.hermes/auth.json
```

Entries there mean the shadow profile is live.

## model picker shows a stale/removed provider

Wipe in order (shell into the relevant container):

1. Remove the credential pool entry on the gateway side: `hermes auth list` then `hermes auth remove <provider> <index>` (index required, from the list). This also suppresses env-var re-seeding for that provider.
2. Frontend cache: `rm /opt/data/webui/models_cache.json` (webui container).
3. Gateway model-discovery cache: `rm /opt/data/provider_models_cache.json`.
4. Bounce the pod — a running process may hold a stale cache in memory and rewrite deleted files:

   ```shell
   kubectl rollout restart deployment/hermes-agent-tyriis -n hermes-agent
   ```

5. Hard-reload the picker page; caches rebuild lazily on next picker request.

Caches are safe to delete: they regenerate. If a deleted cache reappears with old content, an uncleaned source is still feeding it (shadow `auth.json` is the usual suspect).

## ownership gotcha (webui runs as root)

Files under `/opt/data` written by the webui (e.g. `webui/models_cache.json`, everything under the shadow `.hermes/`)
are root-owned and unreadable by the gateway container. Any manual file surgery under `/opt/data` that may touch
webui-written files must be done from the webui container (root shell via k9s), not the gateway container.

## approvals

- `api_server` sessions (and thus gateway-backed WebUI chat on current agent versions) are classified
  **unattended**: no interactive prompt; `approvals.unattended_mode` decides — `deny` (default) blocks flagged
  commands instantly, `approve` auto-allows. Do not flip to `approve` without a deliberate trust decision.
- Approval cards in the WebUI ride the Runs API (see env var above) and additionally require agent-side support (upstream `NousResearch/hermes-agent` approvals PR); on agent <= v2026.9.14 the gate denies before emitting a pending request.
- Interactive approve/deny round-trips currently work on messaging surfaces (Discord) and CLI.
