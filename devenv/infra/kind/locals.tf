# --------------------------------------------------------------------------------
# CONFIGURE LOCALS
# --------------------------------------------------------------------------------

locals {
  kubeconfig_path        = pathexpand("~/.kube/config")
  devenv_name            = "homeops-devenv"
  registry_name          = "homeops-kind-registry"
  registry_port          = "5050"
  registry_internal_port = "5000"
  registry_docker_image  = "registry:3.0.0"
}
