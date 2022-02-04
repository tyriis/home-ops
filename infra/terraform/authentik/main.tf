terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2022.1.1"
    }
  }
}

data "authentik_flow" "default_source_authentication" {
  slug = "default-source-authentication"
}

data "authentik_flow" "default_source_enrollment" {
  slug = "default-source-enrollment"
}

// terraform import module.authentik.authentik_source_oauth.google google
resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  authentication_flow = data.authentik_flow.default_source_authentication.id
  enrollment_flow     = data.authentik_flow.default_source_enrollment.id

  provider_type   = "google"
  consumer_key    = var.consumer_key
  consumer_secret = var.consumer_secret
}

data "authentik_flow" "default_provider_authorization_implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_provider_authorization_explicit_consent" {
  slug = "default-provider-authorization-explicit-consent"
}

// // terraform import module.authentik.authentik_provider_proxy.test 1
// resource "authentik_provider_proxy" "test" {
//   name               = "test"
//   internal_host      = "http://longhorn-frontend.longhorn-system.svc.cluster.local"
//   external_host      = "https://test.${var.cloudflare_domain}"
//   authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
// }

// terraform import module.authentik.authentik_provider_proxy.longhorn 2
resource "authentik_provider_proxy" "longhorn" {
  name               = "longhorn"
  internal_host      = "http://longhorn-frontend.longhorn-system.svc.cluster.local"
  external_host      = "https://longhorn.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_explicit_consent.id
}

// terraform import module.authentik.authentik_service_connection_kubernetes.local 7430e1a3-78a0-40da-8252-857b43d94178
resource "authentik_service_connection_kubernetes" "local" {
  name  = "Local Kubernetes Cluster"
  local = true
}

// // due to the sensitive information inside the config changes are not in diff durring terraform plan/apply
// // should be solved maybe with a template
// // terraform import module.authentik.authentik_outpost.test d661b30f-03c6-4915-8cd0-50a2e668d655
// resource "authentik_outpost" "test" {
//   name               = "test"
//   service_connection = authentik_service_connection_kubernetes.local.id
//   protocol_providers = [
//     authentik_provider_proxy.test.id
//   ]
//   type = "proxy"
//   config = jsonencode(
//     {
//       authentik_host          = "https://authentik.${var.cloudflare_domain}/"
//       authentik_host_browser  = ""
//       authentik_host_insecure = false
//       container_image      = null
//       docker_labels                  = null
//       docker_map_ports               = true
//       docker_network                 = null
//       kubernetes_disabled_components = []
//       kubernetes_image_pull_secrets  = []
//       kubernetes_ingress_annotations = {
//         "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
//         "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
//         "hajimari.io/icon"                                 = "harddisk"
//         "hajimari.io/enable"                               = "true"
//         "hajimari.io/appName"                              = "test"
//       }
//       kubernetes_ingress_secret_name = "authentik-outpost-tls"
//       kubernetes_namespace           = "secops"
//       kubernetes_replicas            = 1
//       kubernetes_service_type        = "ClusterIP"
//       log_level                      = "debug"
//       object_naming_template         = "authentik-outpost-%(name)s"
//     }
//   )
// }


// terraform import module.authentik.authentik_outpost.longhorn bf8b43b1-7910-4ae2-857c-0fb381ff5ea0
resource "authentik_outpost" "longhorn" {
  name               = "longhorn"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.longhorn.id
  ]
  type = "proxy"
  config = jsonencode(
    {
      authentik_host                 = "https://authentik.${var.cloudflare_domain}/"
      authentik_host_browser         = ""
      authentik_host_insecure        = false
      container_image                = null
      docker_labels                  = null
      docker_map_ports               = true
      docker_network                 = null
      kubernetes_disabled_components = []
      kubernetes_image_pull_secrets  = []
      kubernetes_ingress_annotations = {
        "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        "hajimari.io/icon"                                 = "harddisk"
        "hajimari.io/enable"                               = "true"
        "hajimari.io/appName"                              = "longhorn"
      }
      kubernetes_ingress_secret_name = "outpost-longhorn-cert"
      kubernetes_namespace           = "authentik-system"
      kubernetes_replicas            = 1
      kubernetes_service_type        = "ClusterIP"
      log_level                      = "debug"
      object_naming_template         = "outpost-%(name)s"
    }
  )
}

resource "authentik_application" "longhorn" {
  name              = "longhorn"
  slug              = "longhorn"
  protocol_provider = authentik_provider_proxy.longhorn.id
  meta_description  = "longhorn storage ui"
  meta_icon         = "fa://fa-hdd"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://longhorn.${var.cloudflare_domain}"
}
