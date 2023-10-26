<!-- markdownlint-disable MD033 -->

# Terraform infrastructure as code for home-ops

<details>
  <summary style="font-size:1.2em;">Table of Contents</summary>
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Usage](#usage)
  - [Limitations](#limitations)
- [Prerequisites](#prerequisites)
  - [Requirements](#requirements)
  - [Providers](#providers)
  - [Modules](#modules)
  - [Resources](#resources)
  - [Inputs](#inputs)
  - [Outputs](#outputs)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
</details>

## Usage

```bash
terraform apply
```

### Limitations

## Prerequisites

- [Terraform](https://www.terraform.io/) (tested with 1.0.1)

optional: (dev-prerequisites)

- [pre-commit](https://pre-commit.com/)
- [yamllint](https://github.com/adrienverge/yamllint)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs)
- [tflint](https://github.com/terraform-linters/tflint)

<!-- prettier-ignore-start -->
<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | <= 1.6.2 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 4.17.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | >= 4.18.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | 3.4.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 1.13.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.6.1 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | 1.0.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | 4.0.4 |
| <a name="requirement_vault"></a> [vault](#requirement\_vault) | >= 3.2.1 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.0.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloudflare"></a> [cloudflare](#module\_cloudflare) | ./cloudflare | n/a |

### Resources

| Name | Type |
|------|------|
| [sops_file.cloudflare_secrets](https://registry.terraform.io/providers/carlpett/sops/1.0.0/docs/data-sources/file) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_k8s_context"></a> [k8s\_context](#input\_k8s\_context) | flux sync target path | `string` | `"admin@talos-flux"` | no |

### Outputs

No outputs.
<!-- END_TF_DOCS -->
<!-- prettier-ignore-end -->
