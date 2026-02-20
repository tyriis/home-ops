# flux/alerts

Kustomize component that adds Flux notification resources to a namespace — a Flux `Alert` watching all Flux objects and an Alertmanager `Provider` pointing to the in-cluster Alertmanager.

## Variables

None. This component has no substitution variables.

## Usage

Add the component to your namespace-level `kustomization.yaml`:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: observability
components:
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./some-app/flux-sync.yaml
  # ...
```

## Notes

- Creates an `Alert` named `alertmanager` that fires on `error`-severity events from all `FluxInstance`, `GitRepository`, `HelmRelease`, `HelmRepository`, `Kustomization`, and `OCIRepository` objects in the namespace.
- Transient network errors (DNS lookups, TCP timeouts) are excluded via `exclusionList` to reduce noise.
- Creates a `Provider` named `alertmanager` pointing to `http://alertmanager-operated.observability.svc.cluster.local:9093/api/v2/alerts/`.
