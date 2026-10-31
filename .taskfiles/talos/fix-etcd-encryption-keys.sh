#!/usr/bin/env bash
# Rewrites the generated KubeEtcdEncryptionConfig document in talhelper output.
# talhelper 3.1.x emits a single key named "key1" and no identity provider;
# live etcd data is encrypted under key name "key2" (k8s secretbox resolves
# keys by NAME) and legacy plaintext secrets need the identity fallback.
# Without this, apply-config breaks every encrypted/legacy secret read.
# Ref: home-ops incident 2026-10-30 (main cluster).
set -euo pipefail

dir="${1:?usage: fix-etcd-encryption-keys.sh <clusterconfig-dir>}"

# NOTE: `select(...)` as a top-level filter with -i DROPS non-matching
# documents; the parenthesized select on the assignment LHS preserves them.
for f in "${dir}"/*.yaml; do
  base="$(basename "$f")"
  [[ "$base" == "talosconfig" ]] && continue
  if ! yq ea 'select(.kind == "KubeEtcdEncryptionConfig")' "$f" 2>/dev/null | grep -q .; then
    continue
  fi
  if yq ea 'select(.kind == "KubeEtcdEncryptionConfig")' "$f" | grep -q "key2"; then
    continue
  fi
  s="$(yq ea 'select(.kind == "KubeEtcdEncryptionConfig") | .config.resources[0].providers[0].secretbox.keys[0].secret' "$f")"
  S="$s" yq -i '(select(.kind == "KubeEtcdEncryptionConfig").config.resources[0].providers) =
    [{"secretbox": {"keys": [
      {"name": "key2", "secret": strenv(S)},
      {"name": "key1", "secret": strenv(S)}
    ]}},
    {"identity": {}}]' "$f"
done
