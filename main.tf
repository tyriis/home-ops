terraform {
  required_version = ">= 1.0.0"

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
      version = "3.1.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.2.1"
    }
  }
}

module "infra" {
  source                = "./infra"
  github_owner          = var.github_owner
  github_token          = var.github_token
  repository_name       = var.repository_name
  k8s_context           = var.k8s_context
  repository_visibility = var.repository_visibility
  branch                = var.branch
  target_path           = var.target_path
}
