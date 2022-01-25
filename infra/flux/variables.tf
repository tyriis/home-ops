variable "github_owner" {
  type        = string
  description = "github owner"
}

variable "github_token" {
  type        = string
  description = "github token"
}

variable "repository_name" {
  type        = string
  description = "github repository name"
}

variable "repository_visibility" {
  type        = string
  description = "How visible is the github repo"
}

variable "branch" {
  type        = string
  description = "branch name"
}

variable "target_path" {
  type        = string
  description = "flux sync target path"
}

variable "k8s_context" {
  type        = string
  description = "The kuberntes config contex name"
}
