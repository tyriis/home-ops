terraform {
  required_version = "<= 1.9.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.41.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.4"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
  }
}

module "cloudflare" {
  source = "./cloudflare"
}
