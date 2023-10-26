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

### disable local-path-provisioner

TODO: disable local-path-provisioner and setup with helm chart

terraform state rm module.flux.data.flux_sync.main
terraform state rm module.flux.data.kubectl_file_documents.fluxcd_install
terraform state rm module.flux.data.kubectl_file_documents.fluxcd_sync
terraform state rm module.flux.github_repository_deploy_key.main
terraform state rm module.flux.github_repository_deploy_key.talos_flux
terraform state rm module.flux.kubernetes_namespace.flux_system
terraform state rm module.flux.kubernetes_secret.github_deploy_key
terraform state rm module.flux.kubernetes_secret.main
terraform state rm module.flux.kubernetes_secret.sops_age
terraform state rm module.flux.tls_private_key.home_ops
terraform state rm module.flux.tls_private_key.main
