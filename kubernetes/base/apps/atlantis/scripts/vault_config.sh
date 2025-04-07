#!/bin/sh
# This script replaces the ATLANTIS_INJECT_VAULT_CONFIG marker with vault auth_login configuration

# Print directory contents for debugging
echo "Current directory content:"
cat terraform/provider.tf

# Define the replacement text
replacement='  auth_login {\n    path = "auth/kubernetes/login"\n    parameters = {\n      role = "talos-flux-atlantis"\n      jwt  = file("/var/run/secrets/kubernetes.io/serviceaccount/token")\n    }\n  }'

# Find provider.tf files containing both "provider \"vault\"" and the marker
for provider_file in $(grep -l 'provider "vault"' $(find . -name "terraform/provider.tf" -o -name "terraform/providers.tf") | xargs grep -l 'ATLANTIS_INJECT_VAULT_CONFIG'); do
  echo "Found vault provider in $provider_file, injecting auth_login configuration..."

  # Use sed to perform the replacement
  sed -i "s|# ATLANTIS_INJECT_VAULT_CONFIG|$replacement|" "$provider_file"

  echo "Successfully updated $provider_file"
done
