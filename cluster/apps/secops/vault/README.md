# SecOps - Hashicorp Vault

This cluster is using [autounseal-gcpkms][hashicorp-tutorial-unseal-gcpkms] to unseal the vault.

## Prerequisites in GCP

- active keyring and key in KMS
- Service account with IAM Role _Cloud KMS CryptoKey Encrypter/Decrypter_

## Initialize Vault

```sh
vault status          # running, should be recovery seal type: gcpckms, sealed: true)
vault operator init   # initialises with 5 key shares and a key treshold of 3. distribute carefully.
vault status          # should be recovery seal type: shamir, sealed: false
```

Now restart vault. Vault should be automatically unsealed.

## Configure Vault

For configuration and README.md check terraform-vault Repository.

[hashicorp-tutorial-unseal-gcpkms]: https://learn.hashicorp.com/tutorials/vault/autounseal-gcp-kms
