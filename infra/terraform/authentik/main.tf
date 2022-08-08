terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2022.7.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.13.1"
    }
  }
}

data "authentik_flow" "default_source_authentication" {
  slug = "default-source-authentication"
}

data "authentik_flow" "default_source_enrollment" {
  slug = "default-source-enrollment"
}

data "authentik_flow" "default_provider_authorization_implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_provider_authorization_explicit_consent" {
  slug = "default-provider-authorization-explicit-consent"
}

// configure goggle oauth
resource "authentik_source_oauth" "google" {
  name                = "Google"
  slug                = "google"
  authentication_flow = data.authentik_flow.default_source_authentication.id
  enrollment_flow     = data.authentik_flow.default_source_enrollment.id

  provider_type   = "google"
  consumer_key    = var.consumer_key
  consumer_secret = var.consumer_secret
}

// configure service connection
resource "authentik_service_connection_kubernetes" "local" {
  name  = "Local Kubernetes Cluster"
  local = true
}

// this does not work, need to assign google for auth workflow manually currently

// resource "authentik_stage_identification" "google_authentication" {
//   name           = "google-authentication-identification"
//   user_fields    = []
//   sources        = [authentik_source_oauth.google.uuid]
// }

// resource "authentik_stage_authenticator_validate" "google_authentication" {
//   name                  = "google-authentication-mfa-validation"
//   device_classes        = ["static", "totp", "webauthn", "duo", "sms"]
//   not_configured_action = "skip"
// }

// resource "authentik_stage_user_login" "google_authentication" {
//   name = "google-authentication-login"
//   session_duration = "seconds=0"
// }

// resource "authentik_flow" "google_authentication" {
//   name        = "Welcome to authentik!"
//   title       = "Welcome to authentik!"
//   slug        = "google-authentication-flow"
//   designation = "authentication"
// }

// resource "authentik_flow_stage_binding" "google_authentication_identification" {
//   target = authentik_flow.google_authentication.uuid
//   stage  = authentik_stage_identification.google_authentication.id
//   order  = 10
// }

// resource "authentik_flow_stage_binding" "google_authentication_mfa_validation" {
//   target = authentik_flow.google_authentication.uuid
//   stage  = authentik_stage_authenticator_validate.google_authentication.id
//   order  = 30
// }

// resource "authentik_flow_stage_binding" "google_authentication_login" {
//   target = authentik_flow.google_authentication.uuid
//   stage  = authentik_stage_user_login.google_authentication.id
//   order  = 100
// }
