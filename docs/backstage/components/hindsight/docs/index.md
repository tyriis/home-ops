# hindsight

Hindsight ([vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)) is the agent long-term memory server:
structured facts/entities/relations over an embedded PostgreSQL with multi-strategy retrieval and consolidation. It is
the memory backend for **Hermes** (`hindsight` memory provider, bank `hermes`) and for the **coding agents**
(opencode/openchamber plugin, one bank per repo: `coding-agent::<repo>`).

One container per docker host, both deployed via doco-cd as stack `hindsight` (a host directory holding an
include-shim to the shared `docker/deploy/hindsight/compose.yaml`):

| host      | stack directory            | stack file                     | worker id           | consumer                         |
| --------- | -------------------------- | ------------------------------ | ------------------- | -------------------------------- |
| `jarvis`  | `docker/jarvis/hindsight`  | `docker/.doco-cd.jarvis.yaml`  | `hindsight-jarvis`  | Hermes + coding agents on jarvis |
| `agentix` | `docker/agentix/hindsight` | `docker/.doco-cd.agentix.yaml` | `hindsight-agentix` | coding agents on agentix         |

The two instances share nothing — separate volumes, tenant keys and worker ids, each on its own gateway key. Not on
any Kubernetes cluster.

## architecture

- Image `ghcr.io/vectorize-io/hindsight:1.1.0` (digest-pinned, Renovate-managed). The **full** image embeds its own
  PostgreSQL under `/home/hindsight/.pg0` — persisted in named volume `hindsight_data`; `shm_size: 1g` is required for
  it.
- Ports are **loopback-only** on both hosts: API `:8888`, control-plane UI `:9999` (`HOST_BIND=127.0.0.1`). Only local
  agents talk to each instance; neither is published through Traefik.
- Hardened: fixed uid/gid `1000`, `no-new-privileges`, `cap_drop: ALL`, `read_only` rootfs + tmpfs scratch.
- Embeddings + reranker are **local, in-process** (image defaults) on both hosts. Only the LLM is remote:
  `HINDSIGHT_API_LLM_*` point at the new-api gateway (`techtales.ai/v1`), so gateway-side per-bank attribution/limits
  apply when `HINDSIGHT_API_LLM_SEND_BANK_AS_USER=true`.
- Secrets come from each stack's `sops.env` (tenant key, LLM key), encrypted to that host's age recipient. Everything
  reaches the container only via the explicit `environment:` block (doco-cd pattern).

## multi-tenancy

One tenant key per host with the built-in `ApiKeyTenantExtension` — within a host one schema and every key sees every
bank, but jarvis and agentix are fully separate stacks, so the host is the isolation boundary (endpoint-identifying
fields are global, not per-bank, so finer isolation means another stack).

Banks in use:

| bank                   | host    | consumer                                                 |
| ---------------------- | ------- | -------------------------------------------------------- |
| `hermes`               | jarvis  | Hermes agent — recall + auto-retain                      |
| `coding-agent::<repo>` | jarvis  | opencode / open-chamber plugin — created lazily per repo |
| `coding-agent::<repo>` | agentix | coding agents on agentix — created lazily per repo       |

## concurrency guardrails

- `HINDSIGHT_API_LLM_MAX_CONCURRENT=1` on **both** hosts — image default 32 caused a retry storm against vLLM
  (2026-10-23: extraction calls with default reasoning hit the 120s timeout, got cancelled, retried, and pinned ~20
  concurrent streams on the cluster). `enable_thinking=false` in `HINDSIGHT_API_LLM_EXTRA_BODY` is the actual fix; the
  caps are the safety net. Two instances at 1 each therefore hold two gateway slots in total.
- `HINDSIGHT_API_WORKER_MAX_SLOTS=10` (image default) — task slots never raise LLM call volume, the semaphore does.
  The consolidation reservation (image default 2) must stay `<=` this value; the startup validator rejects otherwise.
- Stable `HINDSIGHT_API_WORKER_ID` per host (`hindsight-jarvis`, `hindsight-agentix`) — the poller only reclaims tasks
  claimed by its **own** id; a per-boot id + hard kill leaves rows stranded in `processing` forever (observed
  2026-10-25: a zombie consolidation op blocked every later trigger for 3 nights). Single-replica only — never share
  one id across two live replicas.

## consolidation / nightly drain

- **jarvis**: auto-consolidation-after-retain is off. Retains still extract facts; consolidation queues as
  `pending_consolidation` and is drained nightly by the Hermes cronjob `drain_hindsight_consolidation.py`. A large
  `pending_consolidation` during the day is **expected** — not an alert condition.
- **agentix**: auto-consolidation stays **on** (`HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION=true`) — no Hermes cron exists
  there to drain it. It shares the single LLM slot, so background consolidation is slow, not harmful.

## agentix bring-up

The agentix stack ships with an encrypted `sops.env`: the tenant and control-plane keys are freshly generated, the LLM
key is a placeholder (this repo's age key cannot decrypt that recipient). Read or rotate them with the agentix age key
at hand:

```sh
sops docker/agentix/hindsight/sops.env           # or: SOPS_AGE_KEY_FILE=<agentix key> sops ...
```

- `HINDSIGHT_API_TENANT_API_KEY` — generated; the local agents send it as `Bearer` (put it in agentix's
  `~/.hindsight/coding-agent.json`).
- `HINDSIGHT_CP_ACCESS_KEY` / `HINDSIGHT_CP_DATAPLANE_API_KEY` — generated control-plane credentials for `:9999`.
- `HINDSIGHT_API_LLM_API_KEY` — `REPLACE_ME`: **replace with a real new-api gateway token before the first retain**, or
  every extraction call answers 401 (a token is created in the gateway UI, `techtales.ai`).

Then let doco-cd pick up `docker/.doco-cd.agentix.yaml` (poll, 180s), or start it by hand:
`docker compose --project-directory docker/agentix/hindsight up -d`. Client side, the coding-agent plugin on agentix
needs `~/.hindsight/coding-agent.json` (untracked) with `endpoint: http://127.0.0.1:8888` and the tenant token.

## client config

The coding-agent plugin on jarvis reads `~/.hindsight/coding-agent.json` (untracked — contains the tenant token,
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
