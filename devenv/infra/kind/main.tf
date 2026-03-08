# --------------------------------------------------------------------------------
# CONFIGURE TERRAFORM
# --------------------------------------------------------------------------------

terraform {
  required_version = "1.14.5"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.11.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

# https://registry.terraform.io/providers/tehcyx/kind/latest/docs/resources/cluster
resource "kind_cluster" "flux_devenv" {
  name            = local.devenv_name
  kubeconfig_path = local.kubeconfig_path
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    containerd_config_patches = [
      # configure local oci registry
      <<EOF
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${local.registry_port}"]
            endpoint = ["http://${local.registry_name}:${local.registry_internal_port}"]
        EOF
    ]

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        # ingress label
        <<EOF
          kind: InitConfiguration
          nodeRegistration:
            kubeletExtraArgs:
              node-labels: "ingress-ready=true"
          EOF
      ]
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        listen_address = "127.0.0.1"
      }
    }

    # add 1 observability node
    # node {
    #   role = "worker"
    #   labels = {
    #     "application/role"              = "observability"
    #   }
    #   kubeadm_config_patches = [
    #     # taint
    #     <<EOF
    #     kind: JoinConfiguration
    #     nodeRegistration:
    #       taints:
    #         - key: observability
    #           value: reserved
    #           effect: NoSchedule
    #     EOF
    #   ]
    # }

    # add 1 workload node
    node {
      role = "worker"
      labels = {
        "application/role" = "workload"
      }
    }
  }
}

# create oci registry docker container
resource "docker_image" "registry" {
  name = local.registry_docker_image
}

# Create a container
resource "docker_container" "kind_registry" {
  depends_on = [
    kind_cluster.flux_devenv
  ]
  image   = docker_image.registry.image_id
  name    = local.registry_name
  attach  = false
  restart = "no"
  ports {
    internal = local.registry_internal_port
    external = local.registry_port
    ip       = "127.0.0.1"
  }
  networks_advanced {
    name = "kind"
  }
}
