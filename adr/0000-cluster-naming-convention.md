---
status: accepted
date: 2025-12-14
decision-makers: tyriis, jazzlyn
---

# Kubernetes Cluster Naming: "Forge" and "Nexus"

## Context and Problem Statement

Multiple Kubernetes clusters exist in the homelab environment, each serving different roles (core infrastructure vs. production workloads including Home Assistant, automations, and lab services).
Without a clear, memorable naming convention, contexts are harder to distinguish in tooling, scripts, and day-to-day operations.

The goal is to define an iconic, thematic, and scalable naming scheme and to assign concrete names to the current clusters to reduce operational errors and improve mental mapping.

## Decision Drivers

- Clear differentiation between core infrastructure and production/user-facing workloads

- High memorability and low cognitive load when switching kubectl contexts

- Thematic, "iconic" naming that is enjoyable yet still readable and professional

- Scalability for additional clusters in the future (e.g., test, edge, experimental)

- Minimal disruption to existing tooling and automation

## Considered Options

- Functional names (e.g., core, prod, lab)

- Environment-based names with prefixes/suffixes (e.g., k8s-core, k8s-prod)

- Thematic, non-functional names (e.g., "Forge", "Nexus", "Valhalla", etc.)

- Auto-generated, opaque IDs (e.g., cluster-01, cluster-02)

## Decision Outcome

Chosen option: Thematic, non-functional names ("Forge" and "Nexus"), because they are unique, memorable, map intuitively to the roles of the clusters, and still allow extension of the theme for future clusters.

### Consequences

- Good, because operators can quickly and reliably distinguish clusters in CLI tools, dashboards, and documentation.

- Good, because the theme supports future naming (e.g., "Anvil", "Foundry" related to Forge; "Relay", "Gate", "Portal" related to Nexus).

- Good, because the names remain stable even if roles evolve slightly, avoiding renames when architectural responsibilities shift.

- Bad, because newcomers must learn the mapping between thematic names and functional roles (Forge = core, Nexus = prod).

- Bad, because external automation or integrations that expect environment-like names may require additional mapping or documentation.

## More Information

This decision applies to the current two Kubernetes clusters in home-ops:

Forge: Core infrastructure cluster (foundational services, shared components).

Nexus: Production and user-facing cluster (Home Assistant, automations, helpers, lab workloads).

Future clusters should follow the same thematic style (e.g., names related to creation/engineering for infra-like clusters, and connectivity/hub/portal concepts for user-facing or integration-heavy clusters).
This decision can be revisited if:

The number of clusters grows and introduces ambiguity or name exhaustion.

External collaboration or compliance requirements mandate more functional or environment-encoded names.
