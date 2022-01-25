module "flux" {
  source                = "./flux"
  github_owner          = var.github_owner
  github_token          = var.github_token
  repository_name       = var.repository_name
  k8s_context           = var.k8s_context
  repository_visibility = var.repository_visibility
  branch                = var.branch
  target_path           = var.target_path
}
