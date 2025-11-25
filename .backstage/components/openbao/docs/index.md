# SecOps - OpenBao

This cluster is using [autounseal-gcpkms][hashicorp-tutorial-unseal-gcpkms] to unseal the vault.

## Prerequisites in GCP

- active keyring and key in KMS
- Service account role `roles/cloudkms.cryptoKeyEncrypterDecrypter` and `roles/cloudkms.viewer`, preferably on crypto key level

## Init fresh vault

Vault can be initialized with the seal configuration in place. After initial start it will complain about not be able to unseal.
Exec in Vault Pod and do the following:

```shell
vault status          # running, should be recovery seal type: gcpckms, sealed: true)
vault operator init   # initialises with 5 key shares and a key treshold of 3
vault operator unseal # do this 3 times if seal is not gcpckms
vault status          # should be recovery seal type: shamir, initialized: true, sealed: false
```

**Important**: Save recovery keys and root token securely for disaster recovery.

## Restore vault from raft backup

### Prerequisites

- raft backup locally
- openbao running (red)

### Steps

copy snapshot to openbao pod

```shell
kubectl cp raft.snap secops/openbao-0:/openbao
```

exec into openbao pod

```shell
kubectl exec -it openbao-0 -n secops -- /bin/sh
```

init vault and export new VAULT_TOKEN to env

```shell
export VAULT_TOKEN=$(vault operator init | grep "Initial Root Token" | awk '{print $NF}')
```

restore snapshot

```shell
vault operator raft snapshot restore -force openbao/raft.snap
```

verify

```shell
vault status # should be recovery seal type: gcpckms, initialized: true, sealed: false
```

## Migrate existing vault to auto-unseal with gcpckms

- prepare unseal keys
- stop vault
- add seal definition to config.hcl
- start vault
- unseal using the command `vault operator unseal -migrate`
- enter all remaining unseal keys

```shell
vault status # should be recovery seal type: shamir, sealed: false
```

## Configure auth backends in terraform

### Kubernetes auth backend

Kubernetes auth backend in terraform requires the following information:

```shell
export KUBERNETES_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
export KUBERNETES_CA_CERT=$(kubectl get secret openbao-auth -n secops -o jsonpath="{.data['ca\.crt']}" | base64 --decode)
export SA_TOKEN=$(kubectl get secret openbao-auth -n secops -o jsonpath="{.data.token}" | base64 --decode)
```

**Important**: Service account tokens must be updated when the service account is recreated.

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

<!-- Links -->

[hashicorp-tutorial-unseal-gcpkms]: https://learn.hashicorp.com/tutorials/vault/autounseal-gcp-kms
