---
status: accepted
date: 2025-12-18
decision-makers: [tyriis, Jazzlyn]
---

# Migration to Kubernetes NAS

## Context and Problem Statement

During our evaluation phase to replace Synology NAS, we initially adopted TrueNAS as a potential solution for our home-ops storage system.
However, during Proof of Concept (PoC) testing, several limitations emerged regarding infrastructure-as-code (IaC) compatibility, lifecycle management, and automation.
TrueNAS' lack of a Terraform provider prevents effective GitOps workflows.
Other services such as MinIO, certificate management, and ZFS dataset configuration also proved harder to automate compared to our Kubernetes-based systems managed with Talos, Flux, and Renovate.
This led us to question: _Can we achieve our desired level of automation, maintainability, and observability with TrueNAS, or should we design a Kubernetes-native NAS architecture instead?_

## Decision Drivers

- Infrastructure-as-Code compatibility and lifecycle automation
- GitOps management using Flux and Renovate
- Ease of configuration for NFS shares and datasets
- Secure certificate management (Let's Encrypt)
- Observability and alerting integration
- Reduced attack surface (avoid direct web shell access)
- Architectural consistency with existing Kubernetes clusters
- Minimized maintenance and onboarding of new ecosystems

## Considered Options

- **Option 1:** Continue with TrueNAS as main NAS solution
- **Option 2:** Switch to a Kubernetes-based NAS setup with MinIO and storage node
- **Option 3:** NixOS-based setup for declarative system management

## Decision Outcome

Chosen option: **SSwitch to a Kubernetes-based NAS setup with MinIO and storage node.**

The decision was made because TrueNAS and NixOS do not align with our balance of maintainability, automation, and ecosystem familiarity. TrueNAS lacks IaC capabilities, while NixOS introduces a steep learning curve and unique tooling.
The Kubernetes-native approach fits our existing GitOps model, allows declarative configuration, and unifies system and storage lifecycle management.

### Consequences

- **Good, because** it unifies storage and infrastructure management with existing Flux and Renovate pipelines.
- **Good, because** it allows versioned, declarative infrastructure and reproducible deployments.
- **Good, because** monitoring, alerts, and cert management can be integrated directly with Kubernetes tooling.
- **Bad, because** a single-node cluster is insufficient; requires a minimal two-node setup (one controller, one storage node).
- **Bad, because** initial setup complexity and NFS/ZFS expertise requirements are higher compared to existing NAS solutions.

## Pros and Cons of the Options

### Option 1: TrueNAS as Main NAS

- Good, because it provides a polished UI and stable ZFS features.
- Good, because NFS and SMB are supported out-of-the-box.
- Bad, because limited API stability prevents IaC/Terraform usage.
- Bad, because TrueNAS app management is non-GitOps and difficult to version.
- Bad, because Web-based shell access increases potential attack surface.
- Bad, because service-oriented components like MinIO require manual GUI management.

### Option 2: Kubernetes-based NAS (Chosen)

- Good, because it maintains parity with Talos-managed GitOps clusters.
- Good, because all configurations are stored and versioned as code.
- Good, because monitoring, alerting, and certificate automation are native to Kubernetes.
- Good, because MinIO integrates seamlessly as an operator-managed app.
- Neutral, because hardware efficiency may be lower than optimized NAS systems.
- Bad, because requires additional setup for NFS/ZFS understanding.
- Bad, because two nodes are needed (ZimaBlade as controller, Intel N100 node as data host).

### Option 3: NixOS-based Setup

- Good, because NixOS supports declarative configuration and reproducibility by design.
- Good, because it can meet IaC requirements on a per-host basis.
- Neutral, because it fits the GitOps philosophy but through a separate technology stack.
- Bad, because NixOS requires onboarding a unique language (Nix) and configuration model.
- Bad, because maintaining a parallel ecosystem adds cognitive and operational overhead.
- Bad, because past experience showed its uniqueness makes troubleshooting and automation integration difficult.
- Bad, because the goal is to reduce maintenance and complexity, not introduce another universe of tooling.
