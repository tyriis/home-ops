---
status: accepted
date: 2026-05-16
decision-makers: [tyriis]
---

# Self-host Firecrawl as internal web scraping API on the main cluster

## Context and Problem Statement

The cluster needs a self-hosted web scraping API to support AI/LLM data extraction workflows — extracting clean markdown from web pages, crawling sites, and running structured data extraction.
Firecrawl is the leading open-source tool for this use case, offering a `/scrape` endpoint, `/crawl`, `/map`, and `/extract` APIs with LLM-friendly output.

The previous web extraction backend (Firecrawl Cloud) exhausted its credits during development, blocking research workflows. A self-hosted instance eliminates this dependency and provides unlimited internal usage.

The Firecrawl architecture consists of multiple processes: an API server, several queue workers, a Playwright microservice for browser-based scraping, and backing stores (Redis, PostgreSQL, RabbitMQ).
The deployment must integrate into the existing cluster infrastructure (Flux for GitOps, External Secrets/OpenBao) without external exposure.

## Decision Drivers

- No recurring SaaS costs — self-hosted instance must be cost-free beyond infrastructure.
- Must integrate with existing cluster infrastructure: Flux CD, External Secrets (OpenBao).
- Internal-only access — no public endpoint. All consumers call via Kubernetes Service DNS.
- GitOps-driven — all configuration must be declarative in the `tyriis/home-ops` repo.
- Must use the official Firecrawl Helm chart rather than a generic app-template.
- Must use dedicated namespace (`firecrawl-system`) for isolation.

## Considered Options

- **Option 1: Firecrawl Cloud (SaaS)** — Use the hosted Firecrawl API service. The previous default — credits ran out, blocking all web extraction.
- **Option 2: Self-host via Docker Compose** — Deploy the upstream `docker-compose.yml` on a VM outside the cluster, using bundled Redis and PostgreSQL containers.
- **Option 3: Self-host via official Helm chart** — Use the Firecrawl Helm chart from their `examples/kubernetes/firecrawl-helm/` directory, deployed to `firecrawl-system` namespace with bundled backing stores.
- **Option 4: Self-host via bjw-s app-template on main cluster** — Deploy each Firecrawl component as an individual controller with `bjw-s/app-template` HelmRelease (initially chosen, later replaced by Option 3).

## Decision Outcome

Chosen option: **Option 3: Self-host via official Helm chart on the main cluster** (supersedes previously-chosen Option 4).

This option provides the best alignment with upstream defaults and reduces maintenance burden.
The official Helm chart manages all Firecrawl components (api, worker, extract-worker, nuq-worker,
nuq-prefetch-worker, playwright-service) plus bundled backing stores (Redis, nuq-postgres, RabbitMQ)
natively — eliminating the need to manually maintain 6 controller definitions.

The deployment uses a dedicated `firecrawl-system` namespace for isolation. The Helm chart is sourced
via a Flux GitRepository pointing at the `firecrawl/firecrawl` GitHub repo. Secrets are provisioned
via ExternalSecret from OpenBao, with a Flux post-renderer removing the chart's built-in Secret to
avoid conflicts.

No Gateway API HTTPRoute is defined — the services are internal-only, accessible via standard Kubernetes Service DNS:

- API: `http://firecrawl-api.firecrawl-system.svc.cluster.local:3002`
- Playwright: `http://firecrawl-playwright.firecrawl-system.svc.cluster.local:3000/scrape`

The backing stores are bundled within the chart: Redis (caching, job queues), nuq-postgres (NUQ queue database), and RabbitMQ (message broker). This removes the dependency on Dragonfly and CNPG for Firecrawl specifically.

Deployment is managed via a Flux Kustomization (`flux-sync.yaml`) that depends on `external-secrets-stores`.

### Consequences

- _Good, because_ no SaaS costs — the self-hosted instance has no usage limits or credit exhaustion.
- _Good, because_ fully integrated with the existing GitOps workflow — all config is declarative in the repo, deployed via Flux.
- _Good, because_ uses the official Helm chart — aligns with upstream defaults, reduces manual controller maintenance.
- _Good, because_ dedicated namespace (`firecrawl-system`) provides clear resource isolation.
- _Good, because_ internal-only access via Service DNS provides a strong security boundary — no ingress, no public attack surface.
- _Good, because_ no external infrastructure dependencies — bundled Redis, PostgreSQL, and RabbitMQ simplify operations.
- _Bad, because_ self-hosting Firecrawl requires ongoing maintenance — upstream version updates, security patches, and configuration drift must be managed manually.
- _Bad, because_ no Fire-engine anti-bot features — the self-hosted Playwright service lacks the advanced IP block evasion of the cloud offering.
- _Bad, because_ the official Helm chart is in the `examples/` directory (v0.2.0) — may not be production-hardened or versioned.
- _Bad, because_ the chart does not support disabling bundled Redis or nuq-postgres — they are always deployed even if external alternatives exist.
- _Bad, because_ the chart does not set securityContext — containers run as root by default (acceptable for internal-only service).
- _Bad, because_ secrets must be handled via post-renderer + ExternalSecret workaround — the chart creates its own Secret from values, conflicting with OpenBao.
- _Bad, because_ Supabase authentication features are unavailable in self-hosted mode (acceptable for internal-only use).

## Pros and Cons of the Options

### Option 1: Firecrawl Cloud (SaaS)

- Good, because zero operational overhead — no deployment, no maintenance.
- Good, because includes Fire-engine anti-bot features and IP block evasion.
- Bad, because recurring cost with credit-based pricing — credits ran out during development, blocking all workflows.
- Bad, because data leaves the cluster — all scraped content goes through an external API.
- Bad, because depends on external service availability and rate limits.

### Option 2: Self-host via Docker Compose outside cluster

- Good, because simple to set up — one `docker compose up` command.
- Bad, because not managed by GitOps — manual deployment steps, drift-prone.
- Bad, because VMs add management overhead (OS updates, backups, monitoring).
- Bad, because no integration with cluster networking — access requires separate DNS or port-forward.

### Option 3: Self-host via official Helm chart (chosen)

- Good, because purpose-built for Firecrawl — aligns with upstream defaults.
- Good, because simpler manifest structure than rolling custom controllers.
- Good, because bundled Redis, PostgreSQL, and RabbitMQ eliminate external infra dependencies.
- Good, because Flux GitRepository sourcing pins to a specific repo and commit.
- Bad, because the official Helm chart is in the `examples/` directory — marked as experimental and may not be production-hardened or versioned.
- Bad, because the chart always deploys Redis and nuq-postgres — cannot disable even if external alternatives exist.
- Bad, because no securityContext configuration — containers run as root.
- Bad, because chart creates its own Secret from values — requires post-renderer workaround for ExternalSecret integration.

### Option 4: Self-host via bjw-s app-template on main cluster (superseded)

- Good, because full control over each controller — independent resource requests/limits, probes, and commands per component.
- Good, because native integration with existing cluster infrastructure — CNPG, Dragonfly, ExternalSecret.
- Bad, because the single HelmRelease file is large — six controllers, each with probes, env vars, resource specs, and persistence config.
- Bad, because maintaining the controller configuration is manual — upstream Firecrawl version bumps require updating commands, env vars, and probes by hand.
- Bad, because six controllers in a single HelmRelease creates a moderately large and coupled configuration file.
- Neutral, because no Fire-engine anti-bot features — same limitation as Option 3.

## More Information

- [Firecrawl GitHub](https://github.com/firecrawl/firecrawl) — Upstream project
- [Firecrawl Self-Host Documentation](https://github.com/firecrawl/firecrawl/blob/main/SELF_HOST.md)
- [Firecrawl Helm Chart](https://github.com/firecrawl/firecrawl/tree/main/examples/kubernetes/firecrawl-helm) — Official chart (examples/ directory)
- Secrets are provisioned via ExternalSecret from OpenBao at path `infra/kubernetes/main/firecrawl-system/firecrawl`
- Deployment namespace: `firecrawl-system`
- Flux post-renderer removes the chart's built-in Secret to allow ExternalSecret to manage it
