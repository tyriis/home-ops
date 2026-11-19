#!/usr/bin/env bash
# Render the full machine config for a cluster node, IN MEMORY — nothing on disk.
# Usage: render-config.sh <cluster> <node> [role]   → machine config on stdout
#        role: controlplane (default) | worker
# Sources of truth per cluster: talos/<cluster>/version.yaml + patches/ +
# talsecret.sops.yaml (decrypted through a pipe only).
set -euo pipefail

cluster="${1:?usage: render-config.sh <cluster> <node> [role]}"
node="${2:?usage: render-config.sh <cluster> <node> [role]}"
role="${3:-controlplane}"
case "$role" in
  controlplane | worker) ;;
  *) echo "unknown role: $role (known: controlplane, worker)" >&2; exit 1 ;;
esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/talos/$cluster"
source "$root/.taskfiles/talos/clusters.sh"
cluster_config "$cluster"

# version contract lives in version.yaml (Renovate-annotated); -e fails on a missing key
KUBERNETES_VERSION="$(yq -e -p yaml -o yaml -r '.kubernetesVersion' "$here/version.yaml")"
TALOS_VERSION="$(yq -e -p yaml -o yaml -r '.talosVersion' "$here/version.yaml")"

common="$here/patches/common.patch.yaml"
patch="$here/patches/${node}.patch.yaml"
[[ -f "$common" ]] || { echo "missing patch: $common" >&2; exit 1; }
[[ -f "$patch" ]] || { echo "missing patch: $patch" >&2; exit 1; }

# Derived-state patches (encryption + installer image) are generated at runtime so
# each value has exactly ONE home. tmpfs dir, both files, one trap.
tmpd="$(mktemp --tmpdir -d talos-render-XXXXXX)"
trap 'rm -rf "$tmpd"' EXIT
umask 077
instpatch="$tmpd/installer.patch.yaml"

# Encryption document (key2+key1+identity) is generated from talsecret so the
# key material has exactly ONE home. CONTROL-PLANE ONLY — a worker render
# neither deletes (no gen-bundled doc to delete) nor re-appends it.
# See skill talos-cluster-config, references/encryption-incident.md — key
# NAMES matter (k8s secretbox resolves by name).
encpatch=""
if [[ "$role" == controlplane ]]; then
  encpatch="$tmpd/enc.patch.yaml"
  secretbox="$(sops -d "$here/talsecret.sops.yaml" | yq -p yaml -o yaml -r '.secrets.secretboxencryptionsecret')"
  [[ -n "$secretbox" && "$secretbox" != "null" ]] || { echo "talsecret: secretboxencryptionsecret missing" >&2; exit 1; }
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
# Derived docs announce themselves on stderr (stdout is the config pipe);
# secret material is never printed.
echo "==> derived KubeEtcdEncryptionConfig: key2+key1+identity from talsecret (values not printed)" >&2
fi

# installer.image is DERIVED, never pinned: schematic id (schematic.yaml header) +
# Talos version (version.yaml). tuppr drives upgrades off version.yaml, so a
# manual render can never lag the live installer tag. Node patches keep only
# provisioning.
SCHEMATIC_ID="$(sed -n 's/^# id: \([0-9a-f]\{64\}\)$/\1/p' "$here/schematic.yaml")"
[[ -n "$SCHEMATIC_ID" ]] || { echo "missing '# id: <64 hex>' header: $here/schematic.yaml" >&2; exit 1; }
cat > "$instpatch" <<EOF
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
installer:
  image: factory.talos.dev/metal-installer-secureboot/${SCHEMATIC_ID}:${TALOS_VERSION}
EOF
echo "==> derived installer.image = factory.talos.dev/metal-installer-secureboot/${SCHEMATIC_ID}:${TALOS_VERSION}" >&2

# --with-secrets via process substitution: decrypted talsecret never hits disk.
# common-cp.patch.yaml (control-plane-only docs) is applied only for CP renders —
# a worker apply rejects those kinds. If it disappears, CP renders silently lose
# the docs: catch it with 'task talos:dry' before any util01 apply.
# common.patch.yaml deletes the gen-bundled encryption doc; encpatch re-adds the full
# one LAST so it lands as a single appended document (order is semantic here; CP only).
patches=(--config-patch "@$common")
if [[ "$role" == controlplane && -f "$here/patches/common-cp.patch.yaml" ]]; then
  patches+=(--config-patch "@$here/patches/common-cp.patch.yaml")
fi
patches+=(--config-patch "@$patch" --config-patch "@$instpatch")
if [[ -n "$encpatch" ]]; then
  patches+=(--config-patch "@$encpatch")
fi
exec talosctl gen config "$CLUSTER_NAME" "$ENDPOINT" \
  --with-secrets <(sops -d "$here/talsecret.sops.yaml") \
  --kubernetes-version "$KUBERNETES_VERSION" \
  --talos-version "$TALOS_VERSION" \
  "${patches[@]}" \
  --output-types "$role" -o -
