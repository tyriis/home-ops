# Bootstrap

## Flux

TODO: how to bootstrap flux? check if oci is not a possible attack vector into the cluster?
[ ] assure sops-age secret is provided for cluster-sync

## GitRepo

when flux is up and running, we can apply our manifests

```sh
kubectl apply --server-side -f  kubernetes/flux/repositories/git/home-ops.yaml
kubectl apply --server-side -f  kubernetes/flux/cluster-sync.yaml
```

## GitHub Webhook

Lets define a webhook for our cluster that will be triggered when we push new stuff to our repo

```sh

```
