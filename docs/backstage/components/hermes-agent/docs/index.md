# hermes-agent

Hermes Agent gateway + community WebUI frontend. Two containers in one pod, sharing the PVC mounted at `/opt/data`.

## architecture

- `hermes` container: Hermes gateway, `api_server` on `:8642`, runs as uid `10000`, `HERMES_HOME=/opt/data`.
- `webui` container: `ghcr.io/nesquena/hermes-webui` on `:8787`, runs as uid `10000` (non-root,
  `allowPrivilegeEscalation: false`, all capabilities dropped, `readOnlyRootFilesystem: true`),
  `HOME=/opt/data`, `HERMES_HOME=/opt/data`.
- Both containers deliberately share **one uid and one agent home** — do not split either (see below).
- WebUI chat is gateway-backed: `HERMES_WEBUI_CHAT_BACKEND=gateway` -> `http://localhost:8642`. Auth reuses the shared secret's `API_SERVER_KEY` via `envFrom` fallback (no `HERMES_WEBUI_GATEWAY_API_KEY` set — do not add one).
- `HERMES_WEBUI_GATEWAY_USE_RUNS_API=true` opts the WebUI into the Runs API transport — required for tool-approval cards in the WebUI.

## critical: HERMES_HOME on BOTH containers — and the home is shared on purpose

Both containers MUST set `HERMES_HOME: /opt/data`, and that home is **intentionally shared**. The WebUI reads
the gateway's `state.db` / `sessions/` from it, and that is precisely what makes gateway activity — for example
**Discord sessions** — appear in the WebUI session list. Splitting it (per-container `HERMES_HOME`, a separate
`HOME`, or its own volume) silently removes that visibility. It is a feature, not a leak: do not "clean it up".

The same reasoning fixes the uid: one home written by two containers needs one consistent owner, which is why
`webui` runs as uid `10000` like the gateway. Running the WebUI as root (as it did until PR #10524) produced the
mirror-image failure — root-owned files in the shared PVC that the gateway could not modify.

### legacy shadow profile at `/opt/data/.hermes/`

Before `fd5f09e3e` set `HERMES_HOME` on the webui, it fell back to `$HOME/.hermes` and built a **shadow profile**
at `/opt/data/.hermes/` with its own `auth.json`, `config.yaml` and `state.db`. The model picker then read the
shadow `auth.json` while `hermes auth …` run on the gateway side edited `/opt/data/auth.json`, so removals and
cleanup never took effect. Symptom: a removed provider keeps showing in the WebUI model picker.

That directory still exists on volumes created before the fix, but it is now **orphaned residue** — nothing
writes to it once `HERMES_HOME` is set, its `.env` is 0 bytes, it needs no migration, and it is safe to delete
(~13 MB). It is **not** the cause of a stale model picker on current versions; use the cache procedure below.

If `HERMES_HOME` is ever missing again, the shadow profile comes back and this is how to spot it:

```shell
grep -o 'opencode[a-z-]*' /opt/data/.hermes/auth.json
```

Entries there while `HERMES_HOME` is unset mean the shadow profile is live.

## model picker shows a stale/removed provider

Wipe in order (shell into the relevant container):

1. Remove the credential pool entry on the gateway side: `hermes auth list` then `hermes auth remove <provider> <index>` (index required, from the list). This also suppresses env-var re-seeding for that provider.
2. Frontend cache: `rm /opt/data/webui/models_cache.json` (webui container).
3. Gateway model-discovery cache: `rm /opt/data/provider_models_cache.json`.
4. Bounce the pod — a running process may hold a stale cache in memory and rewrite deleted files: `kubectl rollout restart deployment/hermes-agent-tyriis -n hermes-agent`
5. Hard-reload the picker page; caches rebuild lazily on next picker request.

Caches are safe to delete: they regenerate. If a deleted cache reappears with old content, an uncleaned source is
still feeding it — with `HERMES_HOME` set (as it should be) that is no longer the shadow `auth.json`, so check the
credential pool and the provider's own cache.

## ownership: one uid for the shared PVC

Both containers run as uid/gid `10000`, and the pod sets `fsGroup: 10000` with
`fsGroupChangePolicy: OnRootMismatch`, so every file written to `/opt/data` gets one consistent owner and either
container can read or modify it.

Volumes created while the WebUI still ran as root contain root-owned leftovers. The `init-fix-ownership`
initContainer runs on every start and chowns **only root-owned entries** under `/opt/data` (top two levels,
`lost+found` excluded) — it never recursively chowns the whole PVC, so gateway data that is already correct is
never traversed, and it is a no-op once the tree is clean.

Manual file surgery under `/opt/data` can now be done from either container.

## agent image upgrades

The WebUI's virtualenv (`/opt/data/webui-venv`) is rebuilt whenever the agent source or the WebUI requirements
change: `init-agent-src` stamps a content hash of the agent source into `/tmp/agent-src/.source-rev`, and the WebUI
compares that plus a hash of `/apptoo/requirements.txt` against `$VENV/.build-rev`. Previously the venv was built
only when the directory was missing, so a `ghcr.io/tyriis/hermes-agent` bump never reached the WebUI's Python
environment.

Trade-off: a rebuild deletes and recreates the venv, so a failed `uv pip install` (registry or network trouble)
CrashLoops the WebUI instead of booting with a stale-but-working venv. That matches first-boot behaviour, and the
image tags are pinned by digest, so it should be rare.

## approvals

- `api_server` sessions (and thus gateway-backed WebUI chat on current agent versions) are classified
  **unattended**: no interactive prompt; `approvals.unattended_mode` decides — `deny` (default) blocks flagged
  commands instantly, `approve` auto-allows. Do not flip to `approve` without a deliberate trust decision.
- Approval cards in the WebUI ride the Runs API (see env var above) and additionally require agent-side support (upstream `NousResearch/hermes-agent` approvals PR); on agent <= v2026.9.14 the gate denies before emitting a pending request.
- Interactive approve/deny round-trips currently work on messaging surfaces (Discord) and CLI.
