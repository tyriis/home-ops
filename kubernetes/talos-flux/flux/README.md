# Bootstrap

## Flux

TODO: how to bootstrap flux? check if oci is not a possible attack vector into the cluster?
[ ] assure sops-age secret is provided for cluster-sync

### Manifests

To generate the manifests run:

```console
kustomize build kubernetes/bootstrap > kubernetes/talos-flux/flux/flux-manifests/gotk-components.yaml
```

## GitRepo

when flux is up and running, we can apply our manifests

```sh
kubectl apply --server-side -f  kubernetes/talos-flux/flux/repositories/git/home-ops.yaml
kubectl apply --server-side -f  kubernetes/talos-flux/flux/cluster-sync.yaml
```

## GitHub Webhook

Lets define a webhook for our cluster that will be triggered when we push new stuff to our repo

```sh

```
