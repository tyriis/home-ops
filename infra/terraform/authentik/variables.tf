variable "cloudflare_domain" {
  type        = string
  description = "The cloudflare domain."
  sensitive   = true
}

variable "consumer_secret" {
  type        = string
  description = "The oauth application consumer secret."
  sensitive   = true
}

variable "consumer_key" {
  type        = string
  description = "The oauth application consumer key."
  sensitive   = true
}
