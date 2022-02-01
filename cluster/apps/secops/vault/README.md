# secops - vault

This cluster is using [autounseal-transit](https://learn.hashicorp.com/tutorials/vault/autounseal-transit) to unseal the vault. The transit store is not part of the cluster.

Troubleshooting: if for some reason the `SECRET_VAULT_TOKEN` is not recognized you can follow the steps in the link above to create a new one. (after longer outage/no communication between in cluster vault and unseal vault the token will expire)


### SECOPS
#### Vault auto unseal
https://learn.hashicorp.com/tutorials/vault/autounseal-transit?in=vault/auto-unseal



https://github.com/ricoberger/vault-secrets-operator/issues/104
https://github.com/external-secrets/kubernetes-external-secrets/issues/721
vault write auth/kubernetes/config \
    token_reviewer_jwt="$SA_JWT_TOKEN" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$SA_CA_CRT" \
    issuer="https://kubernetes.default.svc.cluster.local" \
    disable_iss_validation=false

TODO: create terraform pipeline for vault-secrets-operator
