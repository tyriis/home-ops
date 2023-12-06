# create a data source to get the zone id of tyriis.dev
data "cloudflare_zones" "tyriis_dev" {
  filter {
    name = "tyriis.dev"
  }
}

# configure the zone settings for tyriis.dev
resource "cloudflare_zone_settings_override" "tyriis_dev" {
  zone_id = data.cloudflare_zones.tyriis_dev.zones[0]["id"]
  settings {
    always_online            = "off"
    always_use_https         = "off"
    automatic_https_rewrites = "on"
    binary_ast               = "off"
    brotli                   = "on"
    browser_cache_ttl        = 14400
    browser_check            = "on"
    cache_level              = "aggressive"
    challenge_ttl            = 1800
    ciphers                  = []
    cname_flattening         = "flatten_at_root"
    development_mode         = "off"
    early_hints              = "off"
    email_obfuscation        = "on"
    fonts                    = "off"
    h2_prioritization        = "off"
    hotlink_protection       = "off"
    http3                    = "on"
    ip_geolocation           = "on"
    ipv6                     = "on"
    max_upload               = 100
    min_tls_version          = "1.0"
    minify {
      css  = "off"
      html = "off"
      js   = "off"
    }
    mobile_redirect {
      mobile_subdomain = ""
      status           = "off"
      strip_uri        = false
    }
    opportunistic_encryption = "on"
    opportunistic_onion      = "on"
    origin_max_http_version  = "2"
    privacy_pass             = "on"
    pseudo_ipv4              = "off"
    rocket_loader            = "off"
    security_header {
      enabled            = false
      include_subdomains = false
      max_age            = 0
      nosniff            = false
      preload            = false
    }
    security_level      = "medium"
    server_side_exclude = "on"
    ssl                 = "full"
    tls_1_3             = "on"
    tls_client_auth     = "off"
    websockets          = "on"
    zero_rtt            = "off"
  }
}

# create a CNAME record to point tyriis.dev to tyriis.github.io
resource "cloudflare_record" "cname_tyriis_github_io" {
  zone_id = data.cloudflare_zones.tyriis_dev.zones[0]["id"]
  name    = "tyriis.dev"
  value   = "tyriis.github.io"
  type    = "CNAME"
  proxied = true
}

# enable email routing for tyriis.dev
resource "cloudflare_email_routing_settings" "tyriis_dev" {
  zone_id = data.cloudflare_zones.tyriis_dev.zones[0]["id"]
  enabled = "true"
}

# create a cloudflare email routing rule to forward all emails sent to
# me@tyriis.dev to the main email address
resource "cloudflare_email_routing_rule" "tyriis_dev" {
  zone_id = data.cloudflare_zones.tyriis_dev.zones[0]["id"]
  name    = "terraform rule"
  enabled = true

  matcher {
    type  = "literal"
    field = "to"
    value = "me@tyriis.dev"
  }

  action {
    type  = "forward"
    value = [data.sops_file.secrets.data["tyriis_email"]]
  }
}
