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
      version = "4.0.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.2.1"
    }
  }
}
# SSH
locals {
  known_hosts = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  kubernetes_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "tls_private_key" "main" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

data "kubectl_file_documents" "fluxcd_install" {
  content = file("../../cluster/base/flux-system/gotk-components.yaml")
}

data "kubectl_file_documents" "fluxcd_sync" {
  content = file("../../cluster/base/flux-system/gotk-sync.yaml")
}

data "kubectl_file_documents" "fluxcd_kustomization" {
  content = file("../../cluster/base/flux-system/kustomization.yaml")
}

data "flux_sync" "main" {
  target_path = var.target_path
  url         = "ssh://git@github.com/${var.github_owner}/${var.repository_name}.git"
  branch      = var.branch
}

# Kubernetes
resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = "flux-system"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
    ]
  }
}

locals {
  install = [for v in data.kubectl_file_documents.fluxcd_install.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
  sync = [for v in data.kubectl_file_documents.fluxcd_sync.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
}

resource "kubectl_manifest" "install" {
  for_each   = { for v in local.install : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubectl_manifest" "sync" {
  for_each   = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubernetes_secret" "main" {
  depends_on = [kubectl_manifest.install]

  metadata {
    name      = data.flux_sync.main.secret
    namespace = data.flux_sync.main.namespace
    labels    = local.kubernetes_labels
  }

  data = {
    identity       = tls_private_key.main.private_key_pem
    "identity.pub" = tls_private_key.main.public_key_openssh
    known_hosts    = local.known_hosts
  }
}

# GitHub
#tfsec:ignore:github-repositories-private
resource "github_repository" "main" {
  name                   = var.repository_name
  visibility             = var.repository_visibility
  vulnerability_alerts   = true
  has_issues             = true
  delete_branch_on_merge = true
  has_projects           = true
  has_wiki               = true
  topics                 = ["flux", "gitops", "k8s-at-home", "kubernetes", "terraform"]
  // auto_init              = true
}

resource "github_branch_default" "main" {
  repository = github_repository.main.name
  branch     = var.branch
}

resource "github_repository_deploy_key" "main" {
  title      = "k3s.home"
  repository = github_repository.main.name
  key        = tls_private_key.main.public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  repository          = github_repository.main.name
  file                = "${var.target_path}/gotk-components.yaml"
  content             = data.kubectl_file_documents.fluxcd_install.content
  branch              = var.branch
  overwrite_on_create = true
}

resource "github_repository_file" "sync" {
  depends_on = [
    kubernetes_secret.sops_age
  ]
  repository          = github_repository.main.name
  file                = "${var.target_path}/gotk-sync.yaml"
  content             = data.kubectl_file_documents.fluxcd_sync.content
  branch              = var.branch
  overwrite_on_create = true
}

resource "github_repository_file" "kustomize" {
  repository          = github_repository.main.name
  file                = "${var.target_path}/kustomization.yaml"
  content             = data.kubectl_file_documents.fluxcd_kustomization.content
  branch              = var.branch
  overwrite_on_create = true
}

data "vault_generic_secret" "sops_age" {
  path = "kv/${var.repository_name}/flux-system/sops/age"
}

resource "kubernetes_secret" "sops_age" {
  metadata {
    name      = "sops-age"
    namespace = data.flux_sync.main.namespace
    labels    = local.kubernetes_labels
  }

  data = {
    "age.agekey" = var.sops_age_key
  }

  type = "Opaque"
}
