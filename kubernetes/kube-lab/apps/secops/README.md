# Setup

## apply the rbac.yaml

```terminal
kubectl apply --server-side -f kubernetes/kube-lab/apps/secops/namespace.yaml
```

```terminal
kubectl apply --server-side -f kubernetes/kube-lab/apps/secops/rbac.yaml -n secops
```

## openabo config

check [vault documentation](https://developer.hashicorp.com/validated-patterns/vault/vault-kubernetes-auth#configure-kubernetes-authentication), [pr techtales-io/terraform-vault](https://github.com/techtales-io/terraform-vault/pull/77)

```terminal
export SA_TOKEN=$(kubectl get secret openbao-auth -n secops \
  -o jsonpath="{.data.token}" | base64 --decode)
```

```terminal
export KUBERNETES_CA=$(kubectl get secret openbao-auth -n secops \
  -o jsonpath="{.data['ca\.crt']}" | base64 --decode)
```

```terminal
export KUBERNETES_URL=$(kubectl config view --minify \
  -o jsonpath='{.clusters[0].cluster.server}')
```
