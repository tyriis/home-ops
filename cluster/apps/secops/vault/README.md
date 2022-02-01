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


## reconfigure oidc google auth
https://github.com/hashicorp/vault-guides/tree/master/identity/oidc-auth

set your variables
```bash
export VAULT_ADDR=https://vault.mydomain.com
export GOOGLE_API_CLIENT_ID=1234-abc.apps.googleusercontent.com
export GOOGLE_API_CLIENT_SECRET=ABCDE-AbCdeFGdef-abcdEFg
```

configure oidc:

```bash
vault write auth/oidc/config \
    oidc_discovery_url="https://accounts.google.com" \
    oidc_client_id="$GOOGLE_API_CLIENT_ID" \
    oidc_client_secret="$GOOGLE_API_CLIENT_SECRET" \
    default_role="gmail"
```

configure role gmail to allow access to `manager` role (need to be configured independent)
revoke session after 7 days (168h) (assure no `"` arround GOOGLE_API_CLIENT_ID)

```bash
vault write auth/oidc/role/gmail \
    user_claim="sub" \
    bound_audiences=$GOOGLE_API_CLIENT_ID \
    allowed_redirect_uris="$VAULT_ADDR/ui/vault/auth/oidc/oidc/callback" \
    policies=manager \
    ttl=168h
```

set oidc as default backend
https://support.hashicorp.com/hc/en-us/articles/360001922527-Configuring-a-Default-UI-Auth-Method

```bash
vault write sys/auth/oidc/tune listing_visibility="unauth"
```
