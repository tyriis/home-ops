// configure auth proxy
resource "authentik_provider_proxy" "longhorn" {
  name               = "longhorn"
  internal_host      = "http://longhorn-frontend.longhorn-system.svc.cluster.local"
  external_host      = "https://longhorn.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
}

// configure application
resource "authentik_application" "longhorn" {
  name              = "longhorn"
  slug              = "longhorn"
  protocol_provider = authentik_provider_proxy.longhorn.id
  meta_description  = "longhorn storage ui"
  meta_icon         = "fa://fa-hdd"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://longhorn.${var.cloudflare_domain}"
}

// configure outpost
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
      kubernetes_ingress_secret_name = "ak-outpost-longhorn-tls"
      kubernetes_namespace           = "authentik-system"
      kubernetes_replicas            = 1
      kubernetes_service_type        = "ClusterIP"
      log_level                      = "debug"
      object_naming_template         = "ak-outpost-%(name)s"
    }
  )
}
