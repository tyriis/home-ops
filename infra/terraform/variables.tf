variable "github_owner" {
  type        = string
  default     = "tyriis"
  description = "github owner"
}

variable "repository_name" {
  type        = string
  default     = "home-ops"
  description = "github repository name"
}

variable "repository_visibility" {
  type        = string
  default     = "public"
  description = "How visible is the github repo"
}

variable "branch" {
  type        = string
  default     = "main"
  description = "branch name"
}

variable "target_path" {
  type        = string
  default     = "cluster/flux/flux-system"
  description = "flux sync target path"
}

variable "k8s_context" {
  type        = string
  default     = "admin@talos-flux"
  description = "flux sync target path"
}
