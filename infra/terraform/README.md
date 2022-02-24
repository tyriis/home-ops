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

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_authentik"></a> [authentik](#requirement\_authentik) | 2022.2.1 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 3.9.1 |
| <a name="requirement_flux"></a> [flux](#requirement\_flux) | >= 0.9.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | >= 4.18.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | 2.1.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.13.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.6.1 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | 0.6.3 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | 3.1.0 |
| <a name="requirement_vault"></a> [vault](#requirement\_vault) | >= 3.2.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_sops"></a> [sops](#provider\_sops) | 0.6.3 |
| <a name="provider_vault"></a> [vault](#provider\_vault) | 3.3.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_authentik"></a> [authentik](#module\_authentik) | ./authentik | n/a |
| <a name="module_cloudflare"></a> [cloudflare](#module\_cloudflare) | ./cloudflare | n/a |
| <a name="module_flux"></a> [flux](#module\_flux) | ./flux | n/a |

## Resources

| Name | Type |
|------|------|
| [sops_file.authentik_secrets](https://registry.terraform.io/providers/carlpett/sops/0.6.3/docs/data-sources/file) | data source |
| [sops_file.cloudflare_secrets](https://registry.terraform.io/providers/carlpett/sops/0.6.3/docs/data-sources/file) | data source |
| [vault_generic_secret.github_secrets](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/generic_secret) | data source |
| [vault_generic_secret.sops_secrets](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/data-sources/generic_secret) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_branch"></a> [branch](#input\_branch) | branch name | `string` | `"main"` | no |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | github owner | `string` | `"tyriis"` | no |
| <a name="input_k8s_context"></a> [k8s\_context](#input\_k8s\_context) | flux sync target path | `string` | `"flux.k3s.cluster"` | no |
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | github repository name | `string` | `"flux.k3s.cluster"` | no |
| <a name="input_repository_visibility"></a> [repository\_visibility](#input\_repository\_visibility) | How visible is the github repo | `string` | `"public"` | no |
| <a name="input_target_path"></a> [target\_path](#input\_target\_path) | flux sync target path | `string` | `"cluster/base/flux-system"` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
