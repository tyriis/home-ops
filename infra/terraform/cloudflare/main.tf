terraform {
  required_version = "<= 1.8.4"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.33.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.2"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
  }
}

# read data from sops encrypted file
data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.sops.yaml"
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.secrets.data["cloudflare_domain"]
  }
}

resource "cloudflare_zone_settings_override" "cloudflare_settings" {
  zone_id = data.cloudflare_zones.domain.zones[0]["id"]
  settings {
    # /ssl-tls
    ssl = "strict"
    # /ssl-tls/edge-certificates
    always_use_https         = "on"
    min_tls_version          = "1.0"
    opportunistic_encryption = "on"
    tls_1_3                  = "zrt"
    automatic_https_rewrites = "on"
    universal_ssl            = "on"
    # /firewall/settings
    browser_check  = "on"
    challenge_ttl  = 1800
    privacy_pass   = "on"
    security_level = "medium"
    # /speed/optimization
    brotli = "on"
    minify {
      css  = "on"
      js   = "on"
      html = "on"
    }
    rocket_loader = "on"
    # /caching/configuration
    always_online    = "off"
    development_mode = "off"
    # /network
    http3               = "on"
    zero_rtt            = "on"
    ipv6                = "on"
    websockets          = "on"
    opportunistic_onion = "on"
    pseudo_ipv4         = "off"
    ip_geolocation      = "on"
    # /content-protection
    email_obfuscation   = "on"
    server_side_exclude = "on"
    hotlink_protection  = "off"
    # /workers
    security_header {
      enabled = false
    }
  }
}

data "http" "ipv4" {
  url = "https://ipv4.icanhazip.com"
}

resource "cloudflare_record" "ipv4" {
  name    = "ipv4"
  zone_id = data.cloudflare_zones.domain.zones[0]["id"]
  value   = chomp(data.http.ipv4.response_body)
  proxied = true
  type    = "A"
  ttl     = 1
}

// does not work need to migrate domain to cloudflare maybe?
// resource "cloudflare_record" "root" {
//   name    = var.cloudflare_domain
//   zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
//   value   = "ipv4.${var.cloudflare_domain}"
//   proxied = true
//   type    = "CNAME"
//   ttl     = 1
// }

# resource "cloudflare_record" "hajimari" {
#   name    = "hajimari"
#   zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
#   value   = "ipv4.${var.cloudflare_domain}"
#   proxied = true
#   type    = "CNAME"
#   ttl     = 1
# }
