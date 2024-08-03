# Bootstrap

## Cilium

```bash
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/cilium | kubectl apply -n kube-system -f -
kubectl apply -f kubernetes/kube-nas/bootstrap/cilium/l2.yaml
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
sops --decrypt kubernetes/kube-nas/flux/config/sops-age.sops.yaml | kubectl apply -f -
```

### GitRepo

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -f kubernetes/base/flux/repositories/git/home-ops.yaml
```

### Reconcilation

```bash
kubectl apply --server-side -f  kubernetes/kube-nas/flux/flux-system-sync.yaml
```

### disable local-path-provisioner

TODO: disable local-path-provisioner and setup with helm chart
