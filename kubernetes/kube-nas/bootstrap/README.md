# Bootstrap

## Cilium

```bash
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/cilium | kubectl apply -n kube-system -f -
```

## Coredns

```bash
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/coredns | kubectl apply -n kube-system -f -
```

## Metrics Server

```bash
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/metrics-server | kubectl apply -n kube-system -f -
```

## Kubelet CSR approver

```bash
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/kubelet-csr-approver | kubectl apply -n kube-system -f -
```

## Flux

```bash
kubectl apply -k kubernetes/kube-nas/flux/flux-manifests
```

### age key

```bash
sops --decrypt kubernetes/kube-nas/flux/config/age-key.sops.yaml | kubectl apply -f -
```

### GitRepo

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -f  kubernetes/kube-nas/flux/repositories/git/home-ops.yaml
```

### Reconcilation

```bash
kubectl apply --server-side -f  kubernetes/kube-nas/flux/flux-sync.yaml
```
