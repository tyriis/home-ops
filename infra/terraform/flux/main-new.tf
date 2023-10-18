terraform {
  required_version = "<= 1.6.2"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "5.40.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "1.1.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
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

resource "tls_private_key" "home_ops" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

# data "kubectl_file_documents" "fluxcd_install" {
#   content = file("../../cluster/flux/flux-system/gotk-components.yaml")
# }

# data "kubectl_file_documents" "fluxcd_sync" {
#   content = file("../../cluster/flux/flux-system/gotk-sync.yaml")
# }

# data "kubectl_file_documents" "fluxcd_kustomization" {
#   content = file("../../cluster/flux/flux-system/kustomization.yaml")
# }

# data "flux_sync" "main" {
#   target_path = var.target_path
#   url         = "ssh://git@github.com/${var.github_owner}/${var.repository_name}.git"
#   branch      = var.branch
# }

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

# locals {
#   install = [for v in data.kubectl_file_documents.fluxcd_install.documents : {
#     data : yamldecode(v)
#     content : v
#     }
#   ]
#   sync = [for v in data.kubectl_file_documents.fluxcd_sync.documents : {
#     data : yamldecode(v)
#     content : v
#     }
#   ]
# }

# resource "kubectl_manifest" "install" {
#   for_each = { for v in local.install : lower(join("/", compact([
#     v.data.apiVersion,
#     v.data.kind,
#     lookup(v.data.metadata, "namespace", ""),
#     v.data.metadata.name
#   ]))) => v.content }
#   depends_on = [kubernetes_namespace.flux_system]
#   yaml_body  = each.value
#   lifecycle {
#     ignore_changes = [
#       yaml_body
#     ]
#   }
# }

# resource "kubectl_manifest" "sync" {
#   for_each = { for v in local.sync : lower(join("/", compact([
#     v.data.apiVersion,
#     v.data.kind,
#     lookup(v.data.metadata, "namespace", ""),
#     v.data.metadata.name
#   ]))) => v.content }
#   depends_on = [kubernetes_namespace.flux_system]
#   yaml_body  = each.value
#   lifecycle {
#     ignore_changes = [
#       yaml_body
#     ]
#   }
# }

resource "kubernetes_secret" "github_deploy_key" {
  # depends_on = [kubectl_manifest.install]

  metadata {
    name      = "github-deploy-key"
    namespace = "flux-system"
    labels    = local.kubernetes_labels
  }

  data = {
    identity       = tls_private_key.home_ops.private_key_pem
    "identity.pub" = tls_private_key.home_ops.public_key_openssh
    known_hosts    = local.known_hosts
  }
}

# # GitHub
# #tfsec:ignore:github-repositories-private
# resource "github_repository" "main" {
#   name                   = var.repository_name
#   visibility             = var.repository_visibility
#   vulnerability_alerts   = true
#   has_issues             = true
#   delete_branch_on_merge = true
#   has_projects           = true
#   has_wiki               = true
#   topics                 = ["flux", "gitops", "k8s-at-home", "kubernetes", "terraform"]
#   // auto_init              = true
# }

# resource "github_branch_default" "main" {
#   repository = github_repository.main.name
#   branch     = var.branch
# }

resource "github_repository_deploy_key" "talos_flux" {
  title      = "talos-flux"
  repository = "home-ops"
  key        = tls_private_key.home_ops.public_key_openssh
  read_only  = true
}

# resource "github_repository_file" "install" {
#   repository          = github_repository.main.name
#   file                = "${var.target_path}/gotk-components.yaml"
#   content             = data.kubectl_file_documents.fluxcd_install.content
#   branch              = var.branch
#   overwrite_on_create = true
# }

# resource "github_repository_file" "sync" {
#   depends_on = [
#     kubernetes_secret.sops_age
#   ]
#   repository          = github_repository.main.name
#   file                = "${var.target_path}/gotk-sync.yaml"
#   content             = data.kubectl_file_documents.fluxcd_sync.content
#   branch              = var.branch
#   overwrite_on_create = true
# }

# resource "github_repository_file" "kustomize" {
#   repository          = github_repository.main.name
#   file                = "${var.target_path}/kustomization.yaml"
#   content             = data.kubectl_file_documents.fluxcd_kustomization.content
#   branch              = var.branch
#   overwrite_on_create = true
# }

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
