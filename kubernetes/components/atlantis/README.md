# atlantis

Kustomize component that deploys an [Atlantis](https://www.runatlantis.io) instance for Terraform pull request automation.
Each instance manages a single Terraform repository and is configured via patches applied on top of this component.

## Variables

| Variable    | Required | Default     | Description                                                                                  |
| ----------- | -------- | ----------- | -------------------------------------------------------------------------------------------- |
| `APP`       | ✅       | —           | Application name. Used for resource names, the vault secret path, and the Atlantis URL.      |
| `NAMESPACE` | ✅       | —           | Kubernetes namespace to deploy into.                                                         |
| `REPO`      | ✅       | —           | Terraform repository to allow (`ATLANTIS_REPO_ALLOWLIST`). E.g. `github.com/my-org/my-repo`. |
| `GROUP`     | ❌       | `Terraform` | Homepage dashboard group label.                                                              |

## Vault Secret

The component expects an `ExternalSecret` that reads from the path `infra/talos-flux/atlantis-system/${APP}` in the `openbao-backend` `ClusterSecretStore`. The secret must contain:

| Key                          | Description                                                       |
| ---------------------------- | ----------------------------------------------------------------- |
| `ATLANTIS_GH_WEBHOOK_SECRET` | GitHub webhook secret used to validate incoming webhook payloads. |

## Usage

Add the component to your app-layer `kustomization.yaml` and supply patches for any instance-specific configuration. The Flux `Kustomization` must pass the required variables via `postBuild.substitute`:

```yaml
# flux-sync.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app atlantis-techtales-io-terraform-discord
spec:
  targetNamespace: &namespace atlantis-system
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/atlantis-system/techtales-io/terraform-discord
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  prune: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: external-secrets-stores
      namespace: secops
  postBuild:
    substitute:
      APP: *app
      NAMESPACE: *namespace
      REPO: github.com/techtales-io/terraform-discord
      GROUP: Cloud
```

```yaml
# kustomization.yaml (app directory)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
components:
  - ../../../../../components/atlantis
resources:
  - ./external-secret.yaml
patches:
  - path: helm-release.patch.yaml
  - path: external-secret.patch.yaml
```

## Notes

- One component instance per Terraform repository — each app gets its own Atlantis deployment.
- The `ATLANTIS_ATLANTIS_URL` is derived from `{{ .Release.Name }}.techtales.io` (Helm-native, not a substitution variable).
- Redis (Dragonfly) is used as the locking backend at `dragonfly.dragonfly-system.svc.cluster.local`.
- S3 state backend is pre-configured to `https://s3.nas.techtales.io/` with path-style access.
- A `ServiceMonitor` for Prometheus and both a main route and a `/events` webhook route are created automatically.
