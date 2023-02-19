# SecOps - Hashicorp Vault

This cluster is using [autounseal-gcpkms][hashicorp-tutorial-unseal-gcpkms] to unseal the vault.

## Setup auto-unseal

### Prerequisites in GCP

- active keyring and key in KMS
- Service account role `roles/cloudkms.cryptoKeyEncrypterDecrypter` and `roles/cloudkms.viewer`, preferably on crypto key level

### Setup auto-unseal on fresh Vault

add seal definition to config.hcl.

```sh
vault status          # running, should be recovery seal type: gcpckms, sealed: true)
vault operator init   # initialises with 5 key shares and a key treshold of 3
vault status          # should be recovery seal type: shamir, sealed: false
```

### Migrate existing vault to auto-unseal with gcpckms

- prepare unseal keys
- stop vault
- add seal definition to config.hcl
- start vault
- unseal using the command `vault operator unseal -migrate`
- enter all remaining unseal keys

```sh
vault status # should be recovery seal type: shamir, sealed: false
```

## Configure Vault

For configuration and README.md check terraform-vault Repository.

[hashicorp-tutorial-unseal-gcpkms]: https://learn.hashicorp.com/tutorials/vault/autounseal-gcp-kms
