// configure auth proxy
resource "authentik_provider_proxy" "prometheus" {
  name               = "prometheus"
  internal_host      = "http://prometheus-prometheus.observability.svc.cluster.local:9090"
  external_host      = "https://prometheus.${var.cloudflare_domain}"
  authorization_flow = data.authentik_flow.default_provider_authorization_implicit_consent.id
}

// configure application
resource "authentik_application" "prometheus" {
  name              = "prometheus"
  slug              = "prometheus"
  protocol_provider = authentik_provider_proxy.prometheus.id
  meta_description  = "prometheus observability"
  meta_icon         = "fa://fa-clipboard-check"
  meta_publisher    = var.cloudflare_domain
  meta_launch_url   = "https://prometheus.${var.cloudflare_domain}"
}

// configure outpost
resource "authentik_outpost" "prometheus" {
  name               = "prometheus"
  service_connection = authentik_service_connection_kubernetes.local.id
  protocol_providers = [
    authentik_provider_proxy.prometheus.id
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
        "hajimari.io/icon"                                 = "chart-line-stacked"
        "hajimari.io/enable"                               = "true"
        "hajimari.io/appName"                              = "prometheus"
      }
      // kubernetes_ingress_secret_name = "ak-outpost-prometheus-tls"
      kubernetes_namespace    = "authentik-system"
      kubernetes_replicas     = 1
      kubernetes_service_type = "ClusterIP"
      log_level               = "debug"
      object_naming_template  = "ak-outpost-%(name)s"
      // workaround until this is fixed: https://github.com/goauthentik/terraform-provider-authentik/issues/101
      kubernetes_ingress_secret_name = "authentik-outpost-tls"
      kubernetes_disabled_components = ["ingress"]
    }
  )
}

// workaround until this is fixed: https://github.com/goauthentik/terraform-provider-authentik/issues/101
// apply ingress definiton
resource "kubectl_manifest" "ingress_prometheus" {
  yaml_body = templatefile("${path.module}/ingress.yaml.tmpl", {
    name              = "prometheus",
    authentik_version = "2022.1.1",
    outpost_uuid      = authentik_outpost.prometheus.id,
    hajimari_name     = "prometheus",
    hajimari_enabled  = "true",
    hajimari_icon     = "chart-line-stacked",
    domain            = var.cloudflare_domain,
  })
}
