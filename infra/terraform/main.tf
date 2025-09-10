terraform {
  required_version = "<= 1.11.4"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.5.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.1"
    }
  }
}

module "cloudflare" {
  source = "./cloudflare"
}
