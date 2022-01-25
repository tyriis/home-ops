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
  token = var.github_token
}
