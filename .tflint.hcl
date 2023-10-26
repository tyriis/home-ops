config {
  force = false
  disabled_by_default = false
}

rule "terraform_module_pinned_source" {
  enabled = true
  style = "flexible"
  default_branches = ["main", "master", "default", "develop"]
}
