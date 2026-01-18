---
status: accepted
date: 2026-01-17
decision-makers: [tyriis, Jazzlyn]
---

# Make Terraform UniFi Repo Private

## Context and Problem Statement

The Terraform configuration repository managing UniFi network infrastructure was originally planned to be made public to share automation examples, attract feedback, and demonstrate IaC practices.
However, the repository currently contains sensitive information, including:

- Firewall and network rules that could reveal internal structure and segmentation.

- Client names, MAC addresses, and hostnames exposing personal or device identifiers.

- Static IP assignments and internal subnet layouts.

- Site topology and VLAN configurations that could aid potential attackers.

Scrubbing or anonymizing all this information would require continuous oversight and automation to ensure no sensitive details reappear (e.g., after Renovate or device sync updates).
Given the operational importance and privacy implications, the scope of redaction outweighs the benefits of open-sourcing the current repository.

The question is:
Should we make the Terraform UniFi repository public despite embedded sensitive configuration data, or keep it private for security and privacy reasons?

## Decision Drivers

- Protection of sensitive network details (firewall, MACs, clients, IPs).
- Maintaining operational security (device exposure, topology analysis).
- Reducing cognitive and maintenance overhead related to data redaction.
- Consistency with internal-only infrastructure repositories.
- Manageability within GitOps workflows using secret references instead of cleartext values.

## Considered Options

- **Option 1:** Keep the repository fully public as-is.
- **Option 2:** Make the repository private.
- **Option 3:** Anonymize/Encrypt all data with sops and publish a sanitized version.

## Decision Outcome

Chosen option: **Make the Terraform UniFi repository private.**

The decision was made because the repository contains too many sensitive items (firewall rules, client names, IPs, and network details) that cannot easily be sanitized without significant effort and ongoing risk of accidental disclosure.

### Consequences

- **Good, because** private repository ensures internal security and network confidentiality.
- **Good, because** no risk of exposing internal clients, IPs, or UniFi topology.
- **Good, because** the internal GitOps and CI/CD workflows remain unchanged.
- **Bad, because** community reuse potential is reduced, but examples can be shared selectively.
- **Bad, because** no direct public visibility for Terraform UniFi automation patterns.

## Pros and Cons of the Options

### Option 1: Keep Repo Public

- Good, because it demonstrates Terraform best practices to others.
- Good, because others can contribute improvements or ideas.
- Bad, because sensitive data exposure poses real security and privacy risks.
- Bad, because maintaining data hygiene would require complex sanitization pipelines.
- Bad, because it could unintentionally violate local privacy regulations.

### Option 2: Make Repo Private (Chosen)

- Good, because it fully protects confidential and identifying data.
- Good, because internal structure and access control remain undisclosed.
- Good, because it requires no ongoing redaction or metadata sanitization.
- Bad, because public collaboration is limited to separate examples or templates.
- Bad, because it hides potentially useful configurations from the community.

### Option 3: Publish Sanitized Example Repo

- Good, because it allows sharing Terraform patterns safely.
- Good, because examples can still demonstrate automation workflows.
- Bad, because it requires manual or automated anonymization steps.
- Bad, because it duplicates effort and introduces maintenance costs.
- Bad, because example drift risk increases if not automated.
