# Bootstrap

## Cilium

```bash
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/cilium | kubectl apply -n kube-system -f -
```

## Coredns

```bash
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/coredns | kubectl apply -n kube-system -f -
```

## Metrics Server

```bash
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/metrics-server | kubectl apply -n kube-system -f -
```

## Flux

```bash
kubectl create namespace flux-system
kubectl kustomize --enable-helm kubernetes/talos-flux/bootstrap/flux-operator | kubectl apply -n flux-system -f -
```

### age key

```bash
sops --decrypt kubernetes/talos-flux/flux/config/sops-age.sops.yaml | kubectl apply -n flux-system -f -
```

### FluxInstance

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -f kubernetes/talos-flux/apps/flux-system/flux-operator/instance/flux-instance.yaml -n flux-system
```
