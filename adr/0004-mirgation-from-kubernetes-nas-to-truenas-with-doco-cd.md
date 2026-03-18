---
status: accepted
date: 2026-02-23
decision-makers: [tyriis, Jazzlyn]
supersedes: 0001-mirgation-to-kubernetes-nas
---

# Migration from Kubernetes-based NAS to TrueNAS with doco-cd

## Context and Problem Statement

While the Kubernetes-based NAS prototype successfully validated a GitOps-managed storage setup, operational experience showed that the lifecycle of storage infrastructure fundamentally differs from Kubernetes cluster management.
The Kubernetes NAS tied data availability and persistence to the cluster's control plane, creating unnecessary complexity for a subsystem that should be long-lived, fail-safe, and simple to maintain.

In practice, requirements evolved. The storage platform is no longer treated as a cluster component but as a successor to the Synology NAS—focused on stability, minimal upkeep, and trusted ZFS management rather than container orchestration.

To retain automation benefits, we evaluated [doco-cd](https://github.com/kimdre/doco-cd), a small GitOps system for declarative Docker application management.
Doco-cd allows versioned deployments and automated image updates similar to Flux and Renovate pipelines, closing the gap between static NAS operation and automated service updates.

## Decision Drivers

- Simplify storage management lifecycle
- Decouple storage persistence from Kubernetes cluster lifecycle
- Preserve declarative and GitOps-style workflows where applicable
- Improve stability and reliability of storage services (e.g., SMB, NFS, MinIO)
- Retain benefit of ZFS snapshots, replication, and native tooling

## Considered Options

- **Option 1:** Keep Kubernetes-based NAS with MinIO and ZFS node
- **Option 2:** Switch to TrueNAS setup with MinIO and doco-cd

## Decision Outcome

Chosen option: **Switch to TrueNAS setup with MinIO and doco-cd**

TrueNAS provides the stability, simplicity, and ZFS maturity required for long-term data storage. Doco-cd restores lightweight GitOps automation without introducing the operational burden of running a storage-centric Kubernetes cluster.
This approach better matches the intended purpose a self-sustaining, low-maintenance NAS system with declarative container management for extensions and services.

### Consequences

- **Good, because** lifecycle management becomes independent from the Kubernetes cluster.
- **Good, because** doco-cd preserves GitOps workflows for containerized services.
- **Good, because** recovery and upgrades follow a familiar, tested ZFS workflow.
- **Bad, because** monitoring, observability, and certificate handling must be newly integrated outside of Kubernetes.
