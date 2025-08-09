# Bootstrap

## Cilium

```bash
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/cilium | kubectl apply -f -
```

## Coredns

```bash
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/coredns | kubectl apply -n kube-system -f -
```

## Metrics Server

```bash
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/metrics-server | kubectl apply -n kube-system -f -
```

## CSR Approver

```bash
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/kubelet-csr-approver | kubectl apply -n kube-system -f -
```

## Local Storage

```bash
kubectl create namespace democratic-csi
kubectl label --overwrite namespace democratic-csi pod-security.kubernetes.io/enforce=privileged
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/democratic-csi | kubectl apply -n democratic-csi -f -
```

## Flux

```bash
kubectl create namespace flux-system
kubectl kustomize --enable-helm kubernetes/kube-lab/bootstrap/flux-operator | kubectl apply -n flux-system -f -
```

### FluxInstance

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -f kubernetes/kube-lab/apps/flux-system/flux-operator/instance/flux-instance.yaml -n flux-system
```
