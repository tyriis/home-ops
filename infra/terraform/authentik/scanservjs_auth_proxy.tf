// configure auth proxy
#tfsec:ignore:general-secrets-no-plaintext-exposure
resource "authentik_provider_proxy" "scanservjs" {
  name               = "scanservjs"
  internal_host      = "http://scanservjs.hardware.svc.cluster.local:8080"
  external_host      = "https://scanservjs.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
  token_validity     = "days=30"
}

// configure application
resource "authentik_application" "scanservjs" {
  name              = "scanservjs"
  slug              = "scanservjs"
  protocol_provider = authentik_provider_proxy.scanservjs.id
  meta_description  = "scanservjs application"
  meta_icon         = "https://www.iconhot.com/icon/png/token/256/scanner-7.png"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://scanservjs.${var.cloudflare_domain}"
  open_in_new_tab   = false
}

// configure outpost
resource "authentik_outpost" "scanservjs" {
  name               = "scanservjs"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.scanservjs.id
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
        "hajimari.io/icon"                                 = "scanner"
        "hajimari.io/enable"                               = "true"
        "hajimari.io/appName"                              = "scanner"
      }
      kubernetes_ingress_secret_name = "ak-outpost-scanservjs-tls"
      kubernetes_namespace           = "authentik-system"
      kubernetes_replicas            = 1
      kubernetes_service_type        = "ClusterIP"
      log_level                      = "debug"
      object_naming_template         = "ak-outpost-%(name)s"
    }
  )
}
