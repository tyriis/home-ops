#!/usr/bin/env bash
# Render the full machine config for a main-cluster control-plane node, in memory.
# Usage: render-main-config.sh <01|02|03>   → machine config on stdout
# Sources of truth: talos/main/talconfig-* is GONE — patches/ + talsecret.sops.yaml only.
# Replaces talhelper per the official "reproducible machine configuration" workflow:
# https://docs.siderolabs.com/talos/v1.14/configure-your-talos-cluster/system-configuration/reproducible-machine-configuration
set -euo pipefail

node="${1:?usage: render-main-config.sh <talos01|talos02|talos03>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../talos/main" && pwd)"

CLUSTER_NAME="main"
ENDPOINT="https://192.168.100.100:6443"
# version contract: bump only deliberately when regenerating for a Talos/K8s upgrade
KUBERNETES_VERSION="v1.37.2"
TALOS_VERSION="v1.14.5"

# Encryption document (key2+key1+identity) is generated at runtime from talsecret so the
# key material has exactly ONE home. See talos-cluster-config skill,
# references/encryption-incident.md — key NAMES matter (k8s secretbox resolves by name).
secretbox="$(sops -d "$here/talsecret.sops.yaml" | yq -p yaml -r '.secrets.secretboxencryptionsecret')"
[[ -n "$secretbox" && "$secretbox" != "null" ]] || { echo "talsecret: secretboxencryptionsecret missing" >&2; exit 1; }
encpatch="$(mktemp --tmpdir -d talos-enc-XXXXXX)/patch.yaml"
trap 'rm -rf "$(dirname "$encpatch")"' EXIT
umask 077
cat > "$encpatch" <<EOF
---
apiVersion: v1alpha1
kind: KubeEtcdEncryptionConfig
config:
  resources:
    - providers:
        - secretbox:
            keys:
              - name: key2
                secret: ${secretbox}
              - name: key1
                secret: ${secretbox}
        - identity: {}
      resources:
        - secrets
EOF

patch="$here/patches/${node}.patch.yaml"
[[ -f "$patch" ]] || { echo "missing patch: $patch" >&2; exit 1; }

# --with-secrets via process substitution: decrypted talsecret never hits disk.
# common.patch.yaml deletes the gen-bundled encryption doc; encpatch re-adds the full one
# LAST so it lands as a single appended document (order is semantic here).
exec talosctl gen config "$CLUSTER_NAME" "$ENDPOINT" \
  --with-secrets <(sops -d "$here/talsecret.sops.yaml") \
  --kubernetes-version "$KUBERNETES_VERSION" \
  --talos-version "$TALOS_VERSION" \
  --config-patch "@$here/patches/common.patch.yaml" \
  --config-patch "@$patch" \
  --config-patch "@$encpatch" \
  --output-types controlplane -o -
