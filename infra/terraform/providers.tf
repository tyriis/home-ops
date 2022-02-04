provider "vault" {}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = var.k8s_context
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.k8s_context
}

provider "github" {
  owner = var.github_owner
  token = data.vault_generic_secret.github_secrets.data["token"]
}

provider "cloudflare" {
  email   = data.sops_file.cloudflare_secrets.data["cloudflare_email"]
  api_key = data.sops_file.cloudflare_secrets.data["cloudflare_apikey"]
}

provider "authentik" {
  url      = "https://authentik.${data.sops_file.cloudflare_secrets.data["cloudflare_domain"]}"
  token    = data.sops_file.authentik_secrets.data["token"]
  insecure = false
}
