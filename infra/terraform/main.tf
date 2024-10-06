terraform {
  required_version = "<= 1.9.7"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.43.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.5"
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
