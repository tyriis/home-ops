// configure auth proxy
#tfsec:ignore:general-secrets-no-plaintext-exposure
resource "authentik_provider_proxy" "zigbee2mqtt_bridge2" {
  name               = "zigbee2mqtt-bridge2"
  internal_host      = "http://zigbee2mqtt-bridge2.home.svc.cluster.local:8080"
  external_host      = "https://zigbee2mqtt-bridge2.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
  token_validity     = "days=30"
}

// configure application
resource "authentik_application" "zigbee2mqtt_bridge2" {
  name              = "zigbee2mqtt-bridge2"
  slug              = "zigbee2mqtt-bridge2"
  protocol_provider = authentik_provider_proxy.zigbee2mqtt_bridge2.id
  meta_description  = "zigbee2mqtt web ui"
  meta_icon         = "https://www.zigbee2mqtt.io/logo.png"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://zigbee2mqtt-bridge2.${var.cloudflare_domain}"
}

// configure outpost
resource "authentik_outpost" "zigbee2mqtt_bridge2" {
  name               = "zigbee2mqtt-bridge2"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.zigbee2mqtt_bridge2.id
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
        "hajimari.io/icon"                                 = "access-point"
        "hajimari.io/enable"                               = "true"
        "hajimari.io/appName"                              = "zigbee2mqtt-bridge2"
      }
      kubernetes_ingress_secret_name = "ak-outpost-zigbee2mqtt-bridge2-tls"
      kubernetes_namespace           = "authentik-system"
      kubernetes_replicas            = 1
      kubernetes_service_type        = "ClusterIP"
      log_level                      = "debug"
      object_naming_template         = "ak-outpost-%(name)s"
    }
  )
}
