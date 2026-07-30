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

The Firecrawl architecture consists of multiple processes: an API server, several queue workers, a Playwright microservice for browser-based scraping, and backing stores (Redis, PostgreSQL).
The deployment must integrate into the existing cluster infrastructure (CNPG for PostgreSQL, Dragonfly for Redis, Flux for GitOps) without external exposure.

## Decision Drivers

- No recurring SaaS costs — self-hosted instance must be cost-free beyond infrastructure.
- Must integrate with existing cluster infrastructure: Flux CD, CNPG, Dragonfly, External Secrets (OpenBao).
- Internal-only access — no public endpoint. All consumers call via Kubernetes Service DNS.
- Each Firecrawl component must be independently scalable and have appropriate resource allocations for the available node capacity.
- GitOps-driven — all configuration must be declarative in the `tyriis/home-ops` repo.
- Must use existing CNPG Postgres cluster (not a separate or bundled database).
- No Supabase dependency — self-hosted mode does not support Supabase features anyway.

## Considered Options

- **Option 1: Firecrawl Cloud (SaaS)** — Use the hosted Firecrawl API service. The previous default — credits ran out, blocking all web extraction.
- **Option 2: Self-host via Docker Compose** — Deploy the upstream `docker-compose.yml` on a VM outside the cluster, using bundled Redis and PostgreSQL containers.
- **Option 3: Self-host via official Helm chart** — Use the Firecrawl Helm chart from their `examples/kubernetes/firecrawl-helm/` directory.
- **Option 4: Self-host via bjw-s app-template on main cluster** — Deploy each Firecrawl component as an individual controller with `bjw-s/app-template` HelmRelease in the `ai/` namespace, using infrastructure (CNPG, Dragonfly, External Secrets).

## Decision Outcome

Chosen option: **Option 4: Self-host via bjw-s app-template on the main cluster.**

This option provides the best integration with the existing GitOps and cluster infrastructure.
Each Firecrawl process (api, worker, extract-worker, nuq-worker, nuq-prefetch-worker, playwright-service) runs as a separate controller within a single `bjw-s/app-template` HelmRelease,
sharing environment configuration via `envFrom` from an ExternalSecret.
No Gateway API HTTPRoute is defined — the services are internal-only, accessible via standard Kubernetes Service DNS:

- API: `http://firecrawl-api.ai.svc.cluster.local:3002`
- Playwright: `http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape`

The backing stores use existing cluster infrastructure: CNPG (`postgres17`) for the NUQ queue database and Dragonfly for Redis (rate limiting, job queues).
Supabase is not used — self-hosted mode does not support it, and plain PostgreSQL is sufficient.

Deployment is managed via a Flux Kustomization (`flux-sync.yaml`) that depends on `dragonfly-cluster` and `cnpg`.

### Consequences

- _Good, because_ no SaaS costs — the self-hosted instance has no usage limits or credit exhaustion.
- _Good, because_ fully integrated with the existing GitOps workflow — all config is declarative in the repo, deployed via Flux.
- _Good, because_ uses proven cluster infrastructure — CNPG for HA PostgreSQL, Dragonfly for Redis, OpenBao for secrets.
- _Good, because_ internal-only access via Service DNS provides a strong security boundary — no ingress, no public attack surface.
- _Good, because_ each component can be independently scaled and resource-tuned (e.g., api needs 6 Gi memory, nuq-prefetch-worker only needs 1 Gi).
- _Bad, because_ self-hosting Firecrawl requires ongoing maintenance — upstream version updates, security patches, and configuration drift must be managed manually.
- _Bad, because_ no Fire-engine anti-bot features — the self-hosted Playwright service lacks the advanced IP block evasion of the cloud offering.
- _Bad, because_ six controllers in a single HelmRelease creates a moderately large and coupled configuration file.
- _Bad, because_ Supabase authentication features are unavailable (not a concern for internal use, but limits future options).

## Pros and Cons of the Options

### Option 1: Firecrawl Cloud (SaaS)

- Good, because zero operational overhead — no deployment, no maintenance.
- Good, because includes Fire-engine anti-bot features and IP block evasion.
- Bad, because recurring cost with credit-based pricing — credits ran out during development, blocking all workflows.
- Bad, because data leaves the cluster — all scraped content goes through an external API.
- Bad, because depends on external service availability and rate limits.
- Bad, because usage tracking and billing overhead for what is an internal infrastructure component.

### Option 2: Self-host via Docker Compose outside cluster

- Good, because simple to set up — one `docker compose up` command.
- Good, because no Kubernetes expertise needed — can run on any VM.
- Bad, because runs bundled Redis and PostgreSQL containers — duplicates infrastructure that already exists on the cluster (Dragonfly, CNPG).
- Bad, because not managed by GitOps — manual deployment steps, drift-prone.
- Bad, because VMs add management overhead (OS updates, backups, monitoring).
- Bad, because no integration with cluster networking — access requires separate DNS or port-forward.
- Bad, because RabbitMQ is included in the stack unnecessarily (the chosen worker architecture uses the NUQ queue on PostgreSQL instead).

### Option 3: Self-host via official Helm chart

- Good, because purpose-built for Firecrawl — should align with upstream defaults.
- Good, because simpler manifest structure than rolling custom controllers.
- Bad, because the official Helm chart is in the `examples/` directory — marked as experimental and may not be production-hardened or versioned.
- Bad, because the chart likely bundles its own PostgreSQL and Redis sub-charts — conflicting with existing CNPG and Dragonfly.
- Bad, because customization depth may be limited — hard to swap backing stores or tune individual worker resource profiles.
- Bad, because not a standard chart format used elsewhere in the cluster — introduces a new chart dependency and update workflow.

### Option 4: Self-host via bjw-s app-template on main cluster

- Good, because uses the same chart (`bjw-s/app-template`) as the rest of the cluster — consistent patterns for probes, services, persistence, and resource management.
- Good, because full control over each controller — independent resource requests/limits, probes, and commands per component.
- Good, because native integration with existing cluster infrastructure — CNPG via `Database` CR, Dragonfly via Service DNS, secrets via ExternalSecret/OpenBao.
- Good, because internal-only access via Service DNS — no Gateway API HTTPRoute, no public exposure.
- Good, because GitOps-driven via Flux — single Kustomization with dependency declarations.
- Neutral, because the single HelmRelease file is large — six controllers, each with probes, env vars, resource specs, and persistence config.
- Bad, because maintaining the controller configuration is manual — upstream Firecrawl version bumps require updating commands, env vars, and probes by hand.
- Bad, because no Fire-engine anti-bot features — the self-hosted Playwright microservice may be blocked by stricter websites.
- Bad, because Supabase auth features are unavailable in self-hosted mode (acceptable for internal-only use).

## More Information

- [Firecrawl GitHub](https://github.com/nicc/firecrawl) — Upstream project
- [Firecrawl Self-Host Documentation](https://github.com/nicc/firecrawl/blob/main/SELF_HOST.md)
- [bjw-s/app-template Helm Chart](https://bjw-s.github.io/helm-charts/docs/app-template/)
- CNPG database is managed via `dbman.hef.sh/v1alpha3` Database CR pointing at the `postgres17` cluster in `cnpg-system`
- Dragonfly is deployed in the `dragonfly-system` namespace, accessible at `dragonfly.dragonfly-system.svc.cluster.local:6379`
- Secrets are provisioned via ExternalSecret from OpenBao at path `infra/kubernetes/main/ai/firecrawl`
