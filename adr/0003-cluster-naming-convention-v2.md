---
status: accepted
date: 2026-02-01
decision-makers: tyriis, jazzlyn
supersedes: 0000-cluster-naming-convention (2025-12-14)
---

# Kubernetes Cluster Naming: Functional Scheme (main, utility, nas)

## Context and Problem Statement

The original cluster naming convention ("Forge", "Nexus") was chosen for its thematic appeal and memorability.
While effective for a smaller, home-lab environment, the approach no longer aligns with the platform's evolution toward a more professional, production-oriented infrastructure.

As the environment increasingly mirrors enterprise-grade practices - incorporating CI/CD pipelines, observability stacks, and automated deployment flow.
Clarity, consistency, and professional terminology take precedence over creative or thematic expression.

## Decision Drivers

- Alignment with professional infrastructure and naming conventions

- Clear functional association between cluster name and operational purpose

- Simplified interaction with scripts, dashboards, and external integrations

- Scalability for additional clusters while retaining readability and purpose

## Considered Options

- Keep thematic names ("Forge", "Nexus") aligned with home-lab style

- Adopt fully functional, professional-style names (main, utility, nas)

- Use other naming schemes [#7565](https://github.com/tyriis/home-ops/issues/7565)

## Decision Outcome

Chosen option: Functional and professional naming (main, utility, nas)

### Consequences

- Good, because operators can quickly and reliably distinguish clusters in CLI tools, dashboards, and documentation.

- Good, because it adds a more professional touch.

- Bad, because it remove the personal note.

## More Information

This decision applies to the current two Kubernetes clusters in home-ops:

utility: Core infrastructure cluster (foundational services, shared components).

main: Production and user-facing cluster (Home Assistant, automations, helpers, lab workloads).

nas: already exists but has utility build in, considering to split it into 2 systems.
