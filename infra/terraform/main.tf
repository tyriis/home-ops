terraform {
  required_version = "<= 1.9.3"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.38.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.4"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
  }
}

module "cloudflare" {
  source = "./cloudflare"
}
