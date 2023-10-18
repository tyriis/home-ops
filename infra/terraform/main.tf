terraform {
  required_version = "<= 1.6.2"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 4.18.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.6.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.13.1"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">= 0.9.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.2.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.17.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
  }
}

data "vault_generic_secret" "github_secrets" {
  path = "kv/${var.repository_name}/github"
}

data "vault_generic_secret" "sops_secrets" {
  path = "kv/${var.repository_name}/flux-system/sops/age"
}

data "sops_file" "cloudflare_secrets" {
  source_file = "cloudflare-secrets.sops.yaml"
}

module "flux" {
  source                = "./flux"
  github_owner          = var.github_owner
  repository_name       = var.repository_name
  repository_visibility = var.repository_visibility
  branch                = var.branch
  target_path           = var.target_path
  sops_age_key          = data.vault_generic_secret.sops_secrets.data["age.agekey"]
}

module "cloudflare" {
  source            = "./cloudflare"
  cloudflare_domain = data.sops_file.cloudflare_secrets.data["cloudflare_domain"]
}
