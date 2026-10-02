# SearXNG Deployment Design

**Date:** 2026-09-19
**Status:** Approved
**Branch:** `feature/setup-searxng`
**Cluster:** `main` / namespace `ai`

## Overview

Deploy a SearXNG metasearch instance into the `ai` namespace, serving two consumers:

1. **Open WebUI RAG web search** — an in-cluster `ClusterIP` service queried as
   `GET /search?q=<query>&format=json`.
2. **A LAN-only browser search UI** at `https://search.techtales.io`, published through the
   existing `envoy` Gateway in the `networking` namespace.

The instance is not exposed to the public internet.

## Motivation

`kubernetes/main/apps/ai/open-webui/app/helm-release.yaml` contains a commented-out RAG
web-search block. It uses environment variable names that Open WebUI v0.11.3 no longer reads
(see [Research Findings](#open-webui-v0113-integration)), so uncommenting it as written would
silently do nothing. This design replaces it with a correct wiring against a self-hosted
SearXNG instance.

## Goals

- Provide a working, LAN-only SearXNG instance as the RAG search backend for Open WebUI.
- Publish a usable browser search UI on a dedicated hostname.
- Follow existing repository conventions for structure, secrets, DNS, and security context.
- Keep the deployment free of unnecessary runtime dependencies.

## Non-Goals

- Public internet exposure of the search UI.
- Operating the limiter / bot detection (see [Decisions](#decisions)).
- Persisting the favicon cache across restarts.
- Prometheus metrics for SearXNG.
- Curating or trimming the upstream engine list.
- Fixing the Dragonfly component defect found during research (tracked separately).

## Research Findings

### SearXNG 2026.9.19 (`e831fc2a1`)

Findings that contradict widespread community configuration:

| Community convention | Actual behaviour |
| --- | --- |
| Probes on `/stats` | `/stats` is an **HTML statistics page**. `/healthz` returns `text/plain` `OK` and is the correct probe endpoint. It is also explicitly exempt from the limiter. |
| `UWSGI_WORKERS` / `UWSGI_THREADS` | **No-ops.** The image replaced uWSGI with Granian in `2025.7.4-01be261`. Server config is now `GRANIAN_*`. |
| `capabilities.add: [CHOWN, SETGID, SETUID, DAC_OVERRIDE]` | **Legacy.** These date from the uWSGI privilege-drop era. The current entrypoint never drops privileges (Granian does not). |
| `SEARXNG_SECRET` is mandatory | Only required when a `settings.yml` is mounted: `searx/webapp.py` exits with code 1 if `server.secret_key` is left as the literal `ultrasecretkey`. Absent the file, the entrypoint generates one with a random secret. |

Additional facts relied on by this design:

- The image has **no `User` directive** — it runs as **root** by default, with `FORCE_OWNERSHIP=true`
  causing the entrypoint to `chown` `/etc/searxng` and `/var/cache/searxng`. No `PUID`/`PGID` support.
- The `searxng` user is **UID 977 / GID 977**, and the application files are owned by it. Running
  directly as `977:977` skips the chown path and requires no added capabilities.
- With `readOnlyRootFilesystem: true`, the writable locations are **`/tmp`** (default SQLite cache
  DBs, `sxng_cache_*.db`) and **`/var/cache/searxng`** (favicon cache). `/etc/searxng` needs to be
  writable only when `settings.yml` is absent — so a read-only ConfigMap mount with the file present
  is fine.
- `GRANIAN_HOST` is hardcoded to `::` in the image. **This cluster is IPv4-only**
  (`ipam.mode: kubernetes`, `ipv4NativeRoutingCIDR: 10.244.0.0/16`, `routingMode: native`, no IPv6
  configuration), so the host is pinned to `0.0.0.0`.
- `search.formats` defaults to `[html]` only. `format=json` returns **403** unless `json` is added.
- `/metrics` is opt-in: it requires `general.open_metrics` to hold a password **in `settings.yml`**
  (there is no environment override) and is served behind HTTP Basic Auth.
- Result and favicon caches are **SQLite**, not Valkey. Valkey is used only by the limiter/bot
  detection.

### SearXNG limiter

The limiter was investigated and **rejected**. The decisive constraint:

- `searx/botdetection/ip_limit.py` caps non-HTML (`format != html`) requests at **`API_MAX = 4` per
  IP per hour**. This value is **hard-coded** — it is not exposed in `limiter.toml` and cannot be
  raised by configuration.
- Open WebUI is precisely such a client, so it would receive `429` on its fifth RAG search each hour.
- The only mitigation is `botdetection.ip_lists.pass_ip`, which is evaluated before all other checks
  and would require passlisting an ephemeral **pod CIDR**, exempting every pod in it from all bot
  detection. `pass_ip` also outranks `block_ip`.
- A further unverified risk: the sliding-window Lua script calls `redis.call('TIME')`, and Dragonfly
  rejects some commands inside Lua. If rejected, every search returns `500`.
- Additional required configuration if enabled: `trusted_proxies` must contain the Envoy Gateway pod
  CIDR, otherwise all LAN clients collapse into a single shared rate-limit bucket.

For a non-public, LAN-only instance the limiter's threat model (protecting upstream engine IP
reputation from automated abuse) does not apply, while its costs are immediate. Hence
`limiter: false` and **no Valkey/Dragonfly dependency**.

### Open WebUI v0.11.3 integration

Open WebUI renamed the `RAG_WEB_SEARCH_*` family to `WEB_SEARCH_*`. In v0.11.3 the old names are
**not read at all** — there is no backward-compatible alias.

| Old (unread in v0.11.3) | Current |
| --- | --- |
| `ENABLE_RAG_WEB_SEARCH` | `ENABLE_WEB_SEARCH` |
| `RAG_WEB_SEARCH_ENGINE` | `WEB_SEARCH_ENGINE` |
| `RAG_WEB_SEARCH_RESULT_COUNT` | `WEB_SEARCH_RESULT_COUNT` |
| `RAG_WEB_SEARCH_CONCURRENT_REQUESTS` | `WEB_SEARCH_CONCURRENT_REQUESTS` |
| `RAG_WEB_SEARCH_DOMAIN_FILTER_LIST` | `WEB_SEARCH_DOMAIN_FILTER_LIST` |

`SEARXNG_QUERY_URL` kept its name but changed meaning: it must be the **bare `/search` endpoint**.
If the legacy `<query>` placeholder is present, Open WebUI strips everything after `?`. Open WebUI
builds and URL-encodes all query parameters itself, including `format=json`.

| Behaviour | Detail |
| --- | --- |
| `language` | Sent from `SEARXNG_LANGUAGE` (default `all`). **Overrides `search.default_lang`.** |
| `safesearch` | **Hard-coded to `1`** by the client; there is no environment variable. **Overrides `search.safe_search`.** |
| Headers | Sends a fixed set: a `RAG Bot` User-Agent, `Accept: text/html`, `Accept-Encoding: gzip, deflate`, `Accept-Language: en-US,en;q=0.5`. |
| Response schema | Reads `results[]` and maps `url`, `title`, `content`, sorted by `score`. SearXNG's JSON satisfies this. |
| Errors | No retry or backoff; a 403/429/500 surfaces as a failed web search. |

Consequence: `search.default_lang` and `search.safe_search` in `settings.yml` govern **only the
browser UI**. For RAG, language comes from `SEARXNG_LANGUAGE` and safe search is pinned to `1`.

The SearXNG HTTP API does accept per-request `language` and `safesearch` parameters that override
`settings.yml`, but only when `preferences.lock` does not pin them. Invalid values return **HTTP
400** with a JSON error rather than being clamped.

### Chart source verified

The kubesearch install snippet (`oci://ghcr.io/bjw-s-labs/charts/`) is **wrong** — that OCI package
does not exist (`NAME_UNKNOWN`, 404). The authoritative reference, taken from bjw-s-labs' own
`home-ops` repository, is:

```text
oci://ghcr.io/bjw-s-labs/helm/app-template
```

Verified locally with `helm show chart` and `helm template` at version `5.2.1`.

Rendering `app-template` `5.2.1` confirms the pod labels the NetworkPolicy depends on:

```yaml
app.kubernetes.io/name: searxng      # release name, not "app-template"
app.kubernetes.io/instance: searxng
app.kubernetes.io/controller: searxng
```

### Out-of-scope finding: Dragonfly component defect

`kubernetes/components/dragonfly/network-policy.yaml` and `pod-monitor.yaml` select on
`app.kubernetes.io/name: ${APP}-dragonfly`, e.g. `open-webui-dragonfly`. The Dragonfly operator
labels its pods with only:

| Label key | Value |
| --- | --- |
| `app` | `open-webui-dragonfly` (the `Dragonfly` CR name) |
| `app.kubernetes.io/name` | `dragonfly` (constant) |
| `app.kubernetes.io/part-of` | `dragonfly` |

The selector therefore matches **no pods**, so both the repository's NetworkPolicy and its
PodMonitor are inert. Live cluster inspection confirmed two policies coexist in `ai`: the operator's
own `open-webui-dragonfly` policy (which already allows `6379` from same-namespace pods) and the
repository's `open-webui-dragonfly-metrics` policy (which selects nothing).

The practical impact is limited: **per-app Dragonfly metrics are never scraped**, because the
PodMonitor selects nothing and, even if corrected, the repository's `observability/prometheus →
9999` rule would still not apply. There is no `6379` outage, because the operator's own policy
covers it. The correction is to change both selectors to `app: ${APP}-dragonfly`.

This is **out of scope** for this branch and tracked separately.

## Decisions

| # | Decision | Rationale | Rejected alternative |
| --- | --- | --- | --- |
| 1 | Internal RAG backend plus LAN-only browser UI | Matches the motivating use case; no public abuse surface | Public exposure; RAG-only with no UI |
| 2 | Namespace `ai` | Beside its primary consumer; keeps intra-namespace traffic trivial for the default-deny rollout | New `search` namespace; `default` |
| 3 | `app-template` `5.2.1` via per-app `OCIRepository` | Modern artifact delivery; matches podinfo precedent and the kubesearch norm | HelmRepository `bjw-s-charts` at `5.1.0`; HelmRepository at `5.2.1` |
| 4 | `limiter: false`, no Valkey/Dragonfly | The hard-coded `API_MAX = 4`/hour breaks the RAG client; the exemption is broad; the LAN-only threat model does not warrant it | Limiter enabled with pod-CIDR `pass_ip` |
| 5 | Secret via `ExternalSecret` from OpenBao | Matches `open-webui`; `settings.yml` stays reviewable in git and secret-free | Whole `settings.yml` as a Secret; inline `secret_key` |
| 6 | Hostname `search.techtales.io`, `external-dns/unifi: "true"` | Follows the kubesearch `search.${DOMAIN}` convention and the repository's LAN-only DNS pattern | `searxng.techtales.io`; `s.techtales.io` |
| 7 | English UI, `en-US`, `safe_search: 0` | Widest engine coverage; governs the browser UI only | German `de-AT`; safe search moderate |
| 8 | Ingress-only NetworkPolicy | A search engine requires arbitrary internet egress, so an egress rule would be theatre | Full two-way default-deny; defer to the `#8068` rollout |
| 9 | Allow `hermes-agent` on both sides, config untouched | Requested; the ingress rule alone is inert because `hermes-agent` has a default-deny egress policy | Ingress only; also switch `hermes-agent`'s search backend |
| 10 | Wire Open WebUI with correct v0.11.3 names, `SEARXNG_LANGUAGE=en-US` | The existing commented block does not function on the pinned version | Leave commented; leave untouched |
| 11 | Security context UID/GID `977`, no added capabilities, `/healthz` probes | Follows upstream source over community habit | Community root-plus-caps context |

## Architecture

```text
                      LAN browser
                           |
                 https://search.techtales.io
                           |
              +------------+-------------+
              |  envoy Gateway (networking) |
              +------------+-------------+
                           |  :8080
   +-----------------------+------------------------+
   |                 namespace: ai                   |
   |                                                 |
   |  +-----------+   HTTP  +-------------------+    |
   |  | searxng   |<--------| envoy proxy       |    |
   |  | ClusterIP |         +-------------------+    |
   |  |  :8080    |                                  |
   |  +-----+-----+                                  |
   |        ^                                        |
   |        |  /search?q=...&format=json  :8080       |
   |  +-----+----------+                             |
   |  | open-webui     |                             |
   |  +----------------+                             |
   +-------------------------------------------------+
                ^
                |  :8080 (egress rule added to hermes-agent)
   +------------+-------------+
   |  namespace: hermes-agent |
   +--------------------------+
```

Egress to the public internet for search engines is unrestricted, because the NetworkPolicy is
ingress-only.

## Configuration

### `settings.yml`

Mounted read-only at `/etc/searxng/settings.yml`. Contains no secret: `SEARXNG_SECRET` from the
ExternalSecret overrides `server.secret_key` at runtime.

```yaml
use_default_settings: true

general:
  instance_name: SearXNG

search:
  safe_search: 0
  autocomplete: duckduckgo
  default_lang: en-US
  formats:
    - html
    - json

server:
  base_url: https://search.techtales.io/
  limiter: false
  public_instance: false
  image_proxy: true
  method: GET

ui:
  default_locale: en
  default_theme: simple
  theme_args:
    simple_style: auto
```

`use_default_settings: true` inherits the full upstream engine set; engines are deliberately not
curated in this change.

### Image

Pinned by tag and digest, Renovate-managed:

```text
ghcr.io/searxng/searxng:2026.9.19-e831fc2a1@sha256:547fdc19b45510ea1c0bc65ffadab3fcdde1ab1efd7fe696602284ba54d795ca
```

## Security

- **Pod**: `runAsNonRoot: true`, `runAsUser`/`runAsGroup`/`fsGroup: 977`,
  `fsGroupChangePolicy: OnRootMismatch`, `seccompProfile: RuntimeDefault`.
- **Container**: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`,
  `capabilities.drop: [ALL]` and **no `capabilities.add`**.
- **Secret**: `SEARXNG_SECRET` sourced from OpenBao at `infra/kubernetes/main/ai/searxng`; never
  committed.
- **Network**: ingress-only NetworkPolicy permitting same-namespace pods, the `hermes-agent`
  namespace, and the `networking` namespace on port `8080`.
- **Exposure**: LAN-only via UniFi DNS; the Gateway listener allows routes from all namespaces on
  `https`.

## Observability

- Homepage: `gethomepage.dev` annotations on the route.
- Health: `/healthz` used for both readiness and liveness probes.
- Prometheus metrics are deliberately not enabled; `/metrics` would require a plaintext password in
  `settings.yml` behind Basic Auth.
- `reloader.stakater.com/auto: "true"` restarts the pod when the Secret or ConfigMap changes.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Upstream engines rate-limit or block the homelab egress IP | Degraded or missing results | `use_default_settings` keeps many engines; revisit and disable problem engines if observed |
| Single replica | Search unavailable during pod restart | Accepted; SearXNG is stateless and restarts quickly |
| `image_proxy: true` increases pod egress | Slightly higher bandwidth | Accepted; improves privacy and avoids mixed content |
| Favicon cache lost on restart | Cosmetic; brief cold cache | Accepted; avoids a PVC and a VolSync decision |
| `GRANIAN_HOST` assumption | Probes could fail if binding is wrong | Explicitly pinned to `0.0.0.0` for the IPv4-only cluster |

## Follow-ups

1. File a separate issue for the Dragonfly component selector defect
   (`kubernetes/components/dragonfly/{network-policy,pod-monitor}.yaml`), including the live
   evidence that the operator creates its own NetworkPolicy.
2. Revisit the limiter only if the instance is ever exposed publicly. At that point the Open WebUI
   client would need a narrow, stable egress identity so `pass_ip` can be a single address.
3. Consider curating the engine list if upstream engines prove unreliable from the homelab IP.

## References

- SearXNG container installation — <https://docs.searxng.org/admin/installation-docker.html>
- SearXNG settings — <https://docs.searxng.org/admin/settings/index.html>
- SearXNG limiter — <https://docs.searxng.org/admin/searx.limiter.html>
- SearXNG Granian — <https://docs.searxng.org/admin/installation-granian.html>
- SearXNG search API — <https://docs.searxng.org/dev/search_api.html>
- Open WebUI repository — <https://github.com/open-webui/open-webui>
- bjw-s app-template chart — <https://github.com/bjw-s-labs/helm-charts>
- Dragonfly operator — <https://github.com/dragonflydb/dragonfly-operator>
