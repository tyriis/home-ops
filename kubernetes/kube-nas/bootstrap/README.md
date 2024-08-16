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

## OpenEBS Storage

```bash
kubectl create namespace openebs-system
kubectl kustomize --enable-helm kubernetes/kube-nas/bootstrap/openebs | kubectl apply -n openebs-system -f -
```

## Flux

> Currently it is not possible to load it with kubectl, kustomize and helm :(

```bash
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator -n flux-system --create-namespace
```

### age key

```bash
sops --decrypt kubernetes/kube-nas/flux/config/sops-age.sops.yaml | kubectl apply -f - -n flux-system
```

### FluxInstance

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -k kubernetes/kube-nas/flux/instance
```
