config {
  force = false
  disabled_by_default = false
}

# terraform_module_pinned_source rule is enabled by default and can be configured with the following parameters:
# - style: "flexible" (default) or "strict"
# - default_branches: ["main", "master", "default", "develop"] (default)
rule "terraform_module_pinned_source" {
  enabled = true
  style = "flexible"
  default_branches = ["main", "master", "default", "develop"]
}
