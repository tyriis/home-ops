# SecOps - Hashicorp Vault

This cluster is using [autounseal-gcpkms][hashicorp-tutorial-unseal-gcpkms] to unseal the vault.

## Prerequisites in GCP

- active keyring and key in KMS
- Service account role `roles/cloudkms.cryptoKeyEncrypterDecrypter` and `roles/cloudkms.viewer`, preferably on crypto key level

## Init fresh Vault

Vault can be initialized with the seal configuration in place. After initial start it will complain about not be able to unseal.
Exec in Vault Pod and do the following:

```shell
vault status          # running, should be recovery seal type: gcpckms, sealed: true)
vault operator init   # initialises with 5 key shares and a key treshold of 3
vault operator unseal # do this 3 times if seal is not gcpckms
vault status          # should be recovery seal type: shamir, initialized: true, sealed: false
```

Save Recovery Keys and Root token for further recovery/restore operations.

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

## Recover vault from raft backup

- download raft backup
- copy to openbao pod
- exec into openbao pod
- init vault
- export new VAULT_TOKEN to env
- restore snapshot

```shell
kubectl cp raft.snap secops/openbao-0:/openbao
export VAULT_TOKEN=$(vault operator init | grep "Initial Root Token" | awk '{print $NF}')
vault operator raft snapshot restore -force openbao/raft.snap
```

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

<!-- Links -->

[hashicorp-tutorial-unseal-gcpkms]: https://learn.hashicorp.com/tutorials/vault/autounseal-gcp-kms
