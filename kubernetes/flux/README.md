# Bootstrap

## Flux

TODO: how to bootstrap flux?

## GitRepo

when flux is up and running, we can apply our manifests

```sh
kubectl apply --server-side -f  kubernetes/flux/repositories/git/home-ops.yaml
kubectl apply --server-side -f  kubernetes/flux/cluster-sync.yaml
```
