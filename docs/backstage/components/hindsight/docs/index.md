# hindsight

Hindsight ([vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)) is the agent long-term memory server:
structured facts/entities/relations over an embedded PostgreSQL with multi-strategy retrieval and consolidation. It is
the memory backend for **Hermes** (`hindsight` memory provider, bank `hermes`) and for the **coding agents**
(opencode/openchamber plugin, one bank per repo: `coding-agent::<repo>`).

Single container on the **jarvis docker host**, deployed via doco-cd stack `hindsight` (`docker/jarvis/hindsight`
include-shim → shared `docker/deploy/hindsight/compose.yaml`). Not on any Kubernetes cluster.

## architecture

- Image `ghcr.io/vectorize-io/hindsight:1.1.0` (digest-pinned, Renovate-managed). The **full** image embeds its own
  PostgreSQL under `/home/hindsight/.pg0` — persisted in named volume `hindsight_data`; `shm_size: 1g` is required for
  it.
- Ports are **loopback-only**: API `:8888`, control-plane UI `:9999` (`HOST_BIND=127.0.0.1`). Only local agents talk to
  it.
- Hardened: fixed uid/gid `1000`, `no-new-privileges`, `cap_drop: ALL`, `read_only` rootfs + tmpfs scratch.
- Embeddings + reranker are **local, in-process** (image defaults). Only the LLM is remote:
  `HINDSIGHT_API_LLM_*` point at the new-api gateway (`ai.techtales.io`), so gateway-side per-bank attribution/limits
  apply when `HINDSIGHT_API_LLM_SEND_BANK_AS_USER=true`.
- Secrets come from the stack's `sops.env` (tenant key, LLM key). Everything reaches the container only via the
  explicit `environment:` block (doco-cd pattern).

## multi-tenancy

Single shared tenant key with the built-in `ApiKeyTenantExtension` — one schema, all keys see all banks. Deliberate for
a single-host setup; real per-tenant isolation would need a second stack (endpoint-identifying fields are global, not
per-bank).

Banks in use:

| bank                   | consumer                                                 |
| ---------------------- | -------------------------------------------------------- |
| `hermes`               | Hermes agent (this host) — recall + auto-retain          |
| `coding-agent::<repo>` | opencode / open-chamber plugin — created lazily per repo |

## concurrency guardrails

- `HINDSIGHT_API_LLM_MAX_CONCURRENT=2` — image default 32 caused a retry storm against vLLM (2026-10-23: extraction
  calls with default reasoning hit the 120s timeout, got cancelled, retried, and pinned ~20 concurrent streams on the
  cluster). `enable_thinking=false` in `HINDSIGHT_API_LLM_EXTRA_BODY` is the actual fix; the caps are the safety net.
- `HINDSIGHT_API_WORKER_MAX_SLOTS=1` with the consolidation reservation shrunk to 1 — serialize host-side tasks. The
  startup validator rejects reserved > pool.
- Stable `HINDSIGHT_API_WORKER_ID` — the poller only reclaims tasks claimed by its **own** id; a per-boot id + hard
  kill leaves rows stranded in `processing` forever (observed 2026-10-25: a zombie consolidation op blocked every
  later trigger for 3 nights). Single-replica only — never share one id across two live replicas.

## consolidation / nightly drain

Auto-consolidation-after-retain is deferred. Retains still extract facts; consolidation queues as
`pending_consolidation` and is drained nightly by the Hermes cronjob `drain_hindsight_consolidation.py`. A large
`pending_consolidation` during the day is **expected** — not an alert condition.

## client config

The coding-agent plugin on this host reads `~/.hindsight/coding-agent.json` (untracked — contains the tenant token,
never commit it). 2026-10 notes:

- Spawned survey sessions from the opencode2 harness inherit the plugin daemon's cwd (`~`), so they _look_ home-rooted
  even when triggered for a repo elsewhere. Triage by the plugin log (`~/.hindsight/coding-agents-logs/`), not by the
  session directory.
- Path-scoped disable works via top-level `paths` (longest prefix wins): `/home/jarvis: {disabled: true}` with
  longer-prefix re-enables for `~/projects` and `~/research` stops surveys on the home repo without touching real
  repos.
- `survey_refresh` had a re-fire loop (`commits: 0, retry: true` every session start, e.g.
  `coding-agent::multi-file-commit`); top-level `"codebaseSurvey": false` (2026-10-28) disables surveys globally —
  new repos then get git-log seeding but no structural survey. `surveyRefreshCommits: 0` is the surgical alternative.
