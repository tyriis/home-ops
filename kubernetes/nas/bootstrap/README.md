# Bootstrap

## Cilium

```bash
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/cilium | kubectl apply -f -
```

## Coredns

```bash
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/coredns | kubectl apply -n kube-system -f -
```

## Kubelet CSR approver

```bash
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/kubelet-csr-approver | kubectl apply -n kube-system -f -
```

## Metrics Server

```bash
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/metrics-server | kubectl apply -n kube-system -f -
```

## Local Storage

```bash
kubectl create namespace democratic-csi
kubectl label --overwrite namespace democratic-csi pod-security.kubernetes.io/enforce=privileged
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/democratic-csi | kubectl apply -n democratic-csi -f -
```

## Flux

```bash
kubectl create namespace flux-system
kubectl kustomize --enable-helm kubernetes/nas/bootstrap/flux-operator | kubectl apply -n flux-system -f -
```

### age key

```bash
sops --decrypt kubernetes/nas/flux/config/sops-age.sops.yaml | kubectl apply -n flux-system -f -
```

### FluxInstance

when flux is up and running, we can apply our manifests

```bash
kubectl apply --server-side -f kubernetes/nas/apps/flux-system/flux-instance/app/flux-instance.yaml -n flux-system
```
