# Hermes-Agent Multi-Tenant Design

**Goal:** Deploy isolated, secure instances of `hermes-agent` for 4 users (tyriis, jazzlyn, crowlex, techinik) in a dedicated `hermes-agent` namespace. The deployment uses a DRY parameterized Kustomize approach with `bjw-s/app-template` and integrates automatic VolSync backups.

## Architecture

The application uses Flux substitution to instantiate a single HelmRelease definition four times.

```text
kubernetes/main/apps/hermes-agent/
├── namespace.yaml                # Creates 'hermes-agent' namespace
├── kustomization.yaml            # Base kustomization
├── flux-sync.yaml                # Defines the 4 user instances and substitutes variables
└── app/
    ├── kustomization.yaml        # App kustomization, loads volsync
    └── helm-release.yaml         # Parameterized HelmRelease (uses ${APP})
```

## Security Posture

Strict security best practices are applied at the Pod and Container level:

- `runAsUser: 1000` / `runAsGroup: 1000`
- `runAsNonRoot: true`
- `seccompProfile: { type: RuntimeDefault }`
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- `capabilities: { drop: [ALL] }`

## Data & Backups

- The `app/kustomization.yaml` imports `../../../../../components/volsync`.
- A variable `VOLSYNC_SUFFIX: data` ensures the PVC is named `<app-name>-data`.
- VolSync automatically provisions the PersistentVolumeClaim and configures a scheduled Restic backup to MinIO.
- An emptyDir volume `/tmp` is provided since the root filesystem is read-only.

## Variables & Placeholders

Since specific container image and ports weren't provided yet, the following placeholders will be used in the HelmRelease and can be trivially swapped out during implementation or later:

- **Image:** `docker.io/nousresearch/hermes-agent:v2026.5.16@sha256:b6e41c155d6bfce5ad83c5d0fec670086db8a43250e4511c9474134be5482d33`
- **Port:** `8080` (HTTP service)

## Kustomization Example (flux-sync.yaml snippet)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app hermes-agent-tyriis
spec:
  targetNamespace: hermes-agent
  components:
    - ../../../../../components/volsync
  path: ./kubernetes/main/apps/hermes-agent/app
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data
```
