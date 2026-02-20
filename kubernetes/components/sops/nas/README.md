# sops/nas

Kustomize component that deploys the SOPS age key secret for the NAS cluster into the current namespace.
Required by any NAS-cluster application that uses SOPS-encrypted secrets.

## Variables

None. This component has no substitution variables.

## Usage

Add the component to your namespace-level `kustomization.yaml`:

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: cert-manager
components:
  - ../../../components/sops/nas
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./cert-manager/flux-sync.yaml
```

## Notes

- Deploys `kubernetes/nas/flux/config/sops-age.sops.yaml` — the age key used to decrypt SOPS secrets on the NAS cluster.
- This component is intended for the `kubernetes/nas/` cluster only.
- The underlying file is SOPS-encrypted and decrypted at apply time by Flux using the cluster's age key.
