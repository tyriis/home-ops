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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | <= 1.9.5 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | 4.40.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | 3.4.4 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | 1.1.1 |

### Providers

No providers.

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cloudflare"></a> [cloudflare](#module\_cloudflare) | ./cloudflare | n/a |

### Resources

No resources.

### Inputs

No inputs.

### Outputs

No outputs.
<!-- END_TF_DOCS -->
<!-- prettier-ignore-end -->
