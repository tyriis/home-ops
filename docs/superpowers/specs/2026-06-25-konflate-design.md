# Konflate Deployment Design

**Date:** 2026-06-25
**Issue:** [#9364](https://github.com/tyriis/home-ops/issues/9364)
**Scope:** konflate

## Overview

Deploy [Konflate](https://github.com/home-operations/konflate) — a read-only PR review tool for Flux that renders GitOps pull requests as rendered Flux diffs — to the main cluster.

## Architecture

- **Namespace:** `flux-system` (alongside flux-operator and flux-instance)
- **Chart:** OCI Helm chart from `oci://ghcr.io/home-operations/charts/konflate`
- **Source:** OCIRepository with `chartRef` pattern (same as flux-operator)
- **Replicas:** 1 (single-instance, in-memory state; uses `Recreate` strategy)

## Configuration

### Repository

- **Target repo:** `github://tyriis/home-ops` — konflate will review open PRs for this repository
- **Cluster path:** empty (repo root) — correct for the standard `./kubernetes/...` layout

### Features (First Iteration)

| Feature | Setting | Notes |
|---------|---------|-------|
| Status checks | `true` | Post commit status on rendered PRs (needs write token) |
| PR comments | `true` | Post/update summary comment on PRs (needs write token) |
| MCP | `false` | Can be enabled in a future iteration |
| ServiceMonitor | `true` | Prometheus monitoring |
| Persistence | `false` | State lives in emptyDir; can add PVC later |

### Write-back

Write-back (status checks + PR comments) will use a GitHub App. The secrets will be provided by the user and stored in an existing Secret referenced via `secret.existingSecret`.

### Exposure

- **HTTPRoute:** `konflate.techtales.io`
- **Gateway:** `envoy` in `networking` namespace
- **Port:** 8080 (UI/API/websocket)
- **Annotations:** gatus health check endpoint

### Resource Limits

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 50m | (none explicit, burst as needed) |
| Memory | 256Mi | 1Gi |

Based on kubesearch.dev community patterns and onedr0p/home-ops reference implementation.

## File Changes

### New Files

```
kubernetes/main/apps/flux-system/konflate/
├── flux-sync.yaml          # Kustomization CRD pointing at ./app/
└── app/
    ├── kustomization.yaml   # Lists resources
    ├── oci-repository.yaml  # OCIRepository for the Helm chart
    └── helm-release.yaml    # HelmRelease with konflate values
```

### Modified Files

```
kubernetes/main/apps/flux-system/kustomization.yaml  # Add konflate/flux-sync.yaml to resources
```

## Secrets

The user will provide:
- GitHub App credentials (`appClientId` + `appPrivateKey`) or a write token
- Webhook secret
- Push token (optional, for CI-triggered refreshes)

These will be stored in a pre-existing Secret and referenced via `secret.existingSecret`.

## References

- https://github.com/home-operations/konflate
- https://github.com/onedr0p/home-ops/tree/main/kubernetes/apps/flux-system/konflate
- https://kubesearch.dev/hr/ghcr.io-home-operations-charts-konflate
- https://github.com/tyriis/home-ops/issues/9364
