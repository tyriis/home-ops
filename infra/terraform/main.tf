terraform {
  required_version = "<= 1.6.5"
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
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.5"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.2.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.20.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.0"
    }
  }
}

module "cloudflare" {
  source = "./cloudflare"
}
