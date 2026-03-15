#!/bin/sh
# This script replaces the ATLANTIS_INJECT_VAULT_CONFIG marker with vault auth_login configuration

# Define the replacement text
echo $BASE_REPO_NAME
replacement="auth_login {\n    path = \"auth/kube-lab/login\"\n    parameters = {\n      role = \"$BASE_REPO_NAME\"\n      jwt  = file(\"/var/run/secrets/kubernetes.io/serviceaccount/token\")\n    }\n  }"

# Find provider.tf files containing both "provider \"vault\"" and the marker
for provider_file in $(grep -l 'provider "vault"' $(find . -name "provider.tf" -o -name "providers.tf") | xargs grep -l 'ATLANTIS_INJECT_VAULT_CONFIG'); do
  echo "Found vault provider in $provider_file, injecting auth_login configuration..."

  # Use sed to perform the replacement
  sed -i "s|# ATLANTIS_INJECT_VAULT_CONFIG|$replacement|" "$provider_file"

  echo "Successfully updated $provider_file"
done
