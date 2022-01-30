# secops - vault

This cluster is using [autounseal-transit](https://learn.hashicorp.com/tutorials/vault/autounseal-transit) to unseal the vault. The transit store is not part of the cluster.

Troubleshooting: if for some reason the `SECRET_VAULT_TOKEN` is not recognized you can follow the steps in the link above to create a new one.
