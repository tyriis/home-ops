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

- Image: the pinned tag is in `docker/deploy/hindsight/compose.yaml`. Renovate updates the digest-pinned tag.
  The full image includes its own PostgreSQL under `/home/hindsight/.pg0`. The named volume `hindsight_data` stores that data.
  `shm_size: 1g` is required.
- Ports are **loopback-only** on both hosts: API `:8888`, control-plane UI `:9999` (`HOST_BIND=127.0.0.1`). Only local
  agents talk to each instance; neither is published through Traefik.
- Hardened: fixed uid/gid `1000`, `no-new-privileges`, `cap_drop: ALL`, `read_only` rootfs + tmpfs scratch.
- `stop_grace_period: 75s` gives in-flight tasks time to end cleanly. A hard kill leaves tasks in `processing`; see `HINDSIGHT_API_WORKER_ID`.
- Embeddings and the reranker run **locally on CPU**, in-process, with image defaults on both hosts. No API key is needed.
- The LLM is remote. The `HINDSIGHT_API_LLM_*` variables select the new-api gateway at `techtales.ai/v1`. Per-bank gateway
  limits and cost attribution apply when `HINDSIGHT_API_LLM_SEND_BANK_AS_USER` is `true`.
- Secrets come from each stack's `sops.env` (tenant key, LLM key), encrypted to that host's age recipient. Everything
  reaches the container only via the explicit `environment:` block (doco-cd pattern).
- Every API call needs the Bearer token from `sops.env` (`HINDSIGHT_API_TENANT_API_KEY`). The Hermes plugin sends it from its `api_key` config or from `HINDSIGHT_API_KEY`.

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
- `HINDSIGHT_API_WORKER_MAX_SLOTS=10` (image default). Task slots do not change LLM call volume; the semaphore does.
  The consolidation reservation (image default 2) must stay below this value. Equal values leave no slot for retains.
- Stable `HINDSIGHT_API_WORKER_ID` per host (`hindsight-jarvis`, `hindsight-agentix`). The poller reclaims only tasks with
  its own id. After a hard kill, a boot with another id cannot reclaim tasks left in `processing`. Observed 2026-10-25: a
  stuck consolidation blocked the nightly drain for 3 nights. Use one id for one live replica only.

## where values live

- The template sets the safety-net defaults: `HINDSIGHT_API_LLM_EXTRA_BODY`, the timeouts, the retries and backoff, `HINDSIGHT_API_WORKER_MAX_SLOTS`, and `HINDSIGHT_API_REFLECT_WALL_TIMEOUT`.
- Each host `.env` sets site policy: `HINDSIGHT_API_LLM_MAX_CONCURRENT`, `HINDSIGHT_API_LLM_SEND_BANK_AS_USER`, `HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION`, `HINDSIGHT_API_WORKER_ID`, and the LLM provider, endpoint and model.
- A host `.env` variable reaches the container only if the template `environment:` list includes it.
- If you remove a host `.env` line, the template default applies.

## tuning parameters

In the host column, `template` means the host sets no value. `per host` means each host sets its own value.

| Variable                                            | Image default             | Template default         | Host (jarvis / agentix) | What it does and when to change it                                                        |
| --------------------------------------------------- | ------------------------- | ------------------------ | ----------------------- | ----------------------------------------------------------------------------------------- |
| `HINDSIGHT_API_LLM_EXTRA_BODY`                      | none                      | `enable_thinking: false` | template                | Turns thinking off. Keeps extraction calls under the timeout.                             |
| `HINDSIGHT_API_LLM_TIMEOUT`                         | 120                       | 600                      | template                | Time limit per LLM attempt. A timed-out call keeps running upstream.                      |
| `HINDSIGHT_API_REFLECT_WALL_TIMEOUT`                | 300                       | 900                      | template                | Limit per task; refresh excludes LLM queue time. Must exceed `HINDSIGHT_API_LLM_TIMEOUT`. |
| `HINDSIGHT_API_LLM_MAX_RETRIES` (+ backoff)         | 3 / 1.0 / 60.0            | 2 / 2 / 30               | template                | Retries per call; attempts = retries + 1. Then initial and max backoff.                   |
| `HINDSIGHT_API_LLM_MAX_CONCURRENT`                  | 32                        | 2                        | `1` / `1`               | Provider-wide cap on LLM calls. Increase only if the queue is long. Adds gateway load.    |
| `HINDSIGHT_API_WORKER_MAX_SLOTS`                    | 10                        | 10                       | template                | Concurrent tasks per worker. Task count does not change LLM load.                         |
| `HINDSIGHT_API_WORKER_CONSOLIDATION_RESERVED_SLOTS` | 2                         | 2                        | template                | Slots kept for consolidation. Keep `HINDSIGHT_API_WORKER_MAX_SLOTS` above it.             |
| `HINDSIGHT_API_WORKER_ID`                           | unset: container hostname | required (`:?`)          | per host                | Stable id, unique per live replica. Per host: `hindsight-jarvis`, `hindsight-agentix`.    |
| `HINDSIGHT_API_CONSOLIDATION_LLM_MAX_CONCURRENT`    | unset: no extra cap       | 4                        | template                | Effective cap is min(this, `HINDSIGHT_API_LLM_MAX_CONCURRENT`). Global 1 means one call.  |
| `HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION`           | true                      | true                     | `false` / `false`       | `false` queues work as `pending_consolidation`. Needs a nightly drain job.                |
| `HINDSIGHT_API_LLM_SEND_BANK_AS_USER`               | false                     | false                    | `true` / `true`         | Sends the bank id to the gateway and to the upstream provider.                            |

## symptoms and what to adapt

- **Extraction calls time out or retry in a loop:** adapt `HINDSIGHT_API_LLM_EXTRA_BODY` (thinking off), then `HINDSIGHT_API_LLM_TIMEOUT`.
- **Mental-model refreshes pause, or reflect fails with 504:** adapt `HINDSIGHT_API_REFLECT_WALL_TIMEOUT`. It must exceed `HINDSIGHT_API_LLM_TIMEOUT`. One reflect runs up to 10 iterations.
- **Queue latency or gateway rate limits:** adapt `HINDSIGHT_API_LLM_MAX_CONCURRENT`. Increase it only if the gateway has headroom. Decrease it for rate limits.
- **Nightly drain blocked by a task stuck in `processing`:** adapt `HINDSIGHT_API_WORKER_ID`. Keep it stable and unique per live replica. A new id cannot reclaim tasks left in `processing` after a hard kill.
- **`pending_consolidation` grows:** check the nightly drain job first. Set `HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION=true` only if daytime consolidation is acceptable.
- **Startup fails:** `HINDSIGHT_API_WORKER_CONSOLIDATION_RESERVED_SLOTS` is greater than `HINDSIGHT_API_WORKER_MAX_SLOTS`. If both are equal, retains stall, because no slot is left for them.

## consolidation / nightly drain

- **jarvis** and **agentix**: auto-consolidation after retain is off. Retains still extract facts. Consolidation queues as `pending_consolidation`. A nightly drain job on the host processes it.
  A large `pending_consolidation` during the day is **expected**.
- **jarvis**: the drain job is a Hermes cronjob. Its script is not in this repo. It moved to the Hermes profile (`~/.hermes/profiles/jarvis/scripts/`) in `5fb34f060`.
- **agentix**: the drain job runs on the host. It is not defined in this repo.

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
