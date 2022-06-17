<!-- markdownlint-disable MD033 -->

# Terraform infrastructure as code for flux.k3s.cluster

## Table of Contents

1. [Usage](#usage)
2. [Prerequisites](#prerequisites)
3. [Requirements](#requirements)
4. [Providers](#Providers)
5. [Inputs](#inputs)
6. [Outputs](#outputs)

## Usage

```bash
terraform apply
```

### Limitations

- [ ] currently authentik default-authentication-identification must be changed to achieve, maybe we can just create a dedicated one and add it without much effort
- [ ] `kubernetes_ingress_secret_name` and `object_naming_template` can not be written within terraform looks like a bug

## Prerequisites

- [Terraform](https://www.terraform.io/) (tested with 1.0.1)

optional: (dev-prerequisites)

- [pre-commit](https://pre-commit.com/)
- [yamllint](https://github.com/adrienverge/yamllint)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs)
- [tflint](https://github.com/terraform-linters/tflint)

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                        | Version   |
| --------------------------------------------------------------------------- | --------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform)    | >= 1.0.0  |
| <a name="requirement_authentik"></a> [authentik](#requirement_authentik)    | 2022.6.2  |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement_cloudflare) | 3.16.0    |
| <a name="requirement_flux"></a> [flux](#requirement_flux)                   | >= 0.9.0  |
| <a name="requirement_github"></a> [github](#requirement_github)             | >= 4.18.0 |
| <a name="requirement_http"></a> [http](#requirement_http)                   | 2.2.0     |
| <a name="requirement_kubectl"></a> [kubectl](#requirement_kubectl)          | >= 1.13.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement_kubernetes) | >= 2.6.1  |
| <a name="requirement_sops"></a> [sops](#requirement_sops)                   | 0.7.1     |
| <a name="requirement_tls"></a> [tls](#requirement_tls)                      | 3.4.0     |
| <a name="requirement_vault"></a> [vault](#requirement_vault)                | >= 3.2.1  |

## Providers

| Name                                                   | Version |
| ------------------------------------------------------ | ------- |
| <a name="provider_sops"></a> [sops](#provider_sops)    | 0.7.1   |
| <a name="provider_vault"></a> [vault](#provider_vault) | 3.6.0   |

## Modules

| Name                                                              | Source       | Version |
| ----------------------------------------------------------------- | ------------ | ------- |
| <a name="module_authentik"></a> [authentik](#module_authentik)    | ./authentik  | n/a     |
| <a name="module_cloudflare"></a> [cloudflare](#module_cloudflare) | ./cloudflare | n/a     |
| <a name="module_flux"></a> [flux](#module_flux)                   | ./flux       | n/a     |

## Resources

| Name                                                                                                                                   | Type        |
| -------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [sops_file.authentik_secrets](https://registry.terraform.io/providers/carlpett/sops/0.7.1/docs/data-sources/file)                      | data source |
| [sops_file.cloudflare_secrets](https://registry.terraform.io/providers/carlpett/sops/0.7.1/docs/data-sources/file)                     | data source |
| [vault_generic_secret.github_secrets](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/generic_secret) | data source |
| [vault_generic_secret.sops_secrets](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/generic_secret)   | data source |

## Inputs

| Name                                                                                             | Description                    | Type     | Default                      | Required |
| ------------------------------------------------------------------------------------------------ | ------------------------------ | -------- | ---------------------------- | :------: |
| <a name="input_branch"></a> [branch](#input_branch)                                              | branch name                    | `string` | `"main"`                     |    no    |
| <a name="input_github_owner"></a> [github_owner](#input_github_owner)                            | github owner                   | `string` | `"tyriis"`                   |    no    |
| <a name="input_k8s_context"></a> [k8s_context](#input_k8s_context)                               | flux sync target path          | `string` | `"flux.k3s.cluster"`         |    no    |
| <a name="input_repository_name"></a> [repository_name](#input_repository_name)                   | github repository name         | `string` | `"flux.k3s.cluster"`         |    no    |
| <a name="input_repository_visibility"></a> [repository_visibility](#input_repository_visibility) | How visible is the github repo | `string` | `"public"`                   |    no    |
| <a name="input_target_path"></a> [target_path](#input_target_path)                               | flux sync target path          | `string` | `"cluster/base/flux-system"` |    no    |

## Outputs

No outputs.

<!-- END_TF_DOCS -->
