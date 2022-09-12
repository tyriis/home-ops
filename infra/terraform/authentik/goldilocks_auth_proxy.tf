// configure auth proxy
#tfsec:ignore:general-secrets-no-plaintext-exposure
resource "authentik_provider_proxy" "goldilocks" {
  name               = "goldilocks"
  internal_host      = "http://goldilocks-dashboard.observability.svc.cluster.local"
  external_host      = "https://goldilocks.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
  token_validity     = "days=30"
}

// configure application
resource "authentik_application" "goldilocks" {
  name              = "goldilocks"
  slug              = "goldilocks"
  protocol_provider = authentik_provider_proxy.goldilocks.id
  meta_description  = "goldilocks web ui"
  meta_icon         = "fa://fa-flask"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://goldilocks.${var.cloudflare_domain}"
  open_in_new_tab   = false
}

// configure outpost
resource "authentik_outpost" "goldilocks" {
  name               = "goldilocks"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.goldilocks.id
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
        "hajimari.io/icon"                                 = "test-tube"
        "hajimari.io/enable"                               = "true"
        "hajimari.io/appName"                              = "goldilocks"
      }
      kubernetes_ingress_secret_name = "ak-outpost-goldilocks-tls"
      kubernetes_namespace           = "authentik-system"
      kubernetes_replicas            = 1
      kubernetes_service_type        = "ClusterIP"
      log_level                      = "debug"
      object_naming_template         = "ak-outpost-%(name)s"
    }
  )
}
