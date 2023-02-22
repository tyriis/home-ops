variable "github_owner" {
  type        = string
  description = "github owner"
}

variable "repository_name" {
  type        = string
  description = "github repository name"
}

# variable "repository_visibility" {
#   type        = string
#   description = "How visible is the github repo"
# }

variable "branch" {
  type        = string
  description = "branch name"
}

variable "target_path" {
  type        = string
  description = "flux sync target path"
}

variable "sops_age_key" {
  type        = string
  description = "The sops age key used for global encryption."
  sensitive   = true
}
