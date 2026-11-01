#!/usr/bin/env bash
# Generate a cluster's talosconfig (client cert), backfill endpoints/nodes, and
# merge into the central ~/.talos/config. Nodes are REQUIRED as args — gen
# config leaves them empty, and merging an empty entry silently wipes working
# ones. Never call without the node list.
# usage: gen-talosconfig.sh <cluster> <node-ip> [more-node-ips...]
set -euo pipefail

cluster="${1:?usage: gen-talosconfig.sh <cluster> <node-ip> [...]}"
shift
[[ $# -ge 1 ]] || { echo "at least one node-ip required" >&2; exit 1; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/talos/$cluster"
source "$root/.taskfiles/talos/clusters.sh"
cluster_config "$cluster"

kv="$(yq -e -p yaml -o yaml -r .kubernetesVersion "$here/version.yaml")"
tv="$(yq -e -p yaml -o yaml -r .talosVersion "$here/version.yaml")"

out="$here/clusterconfig/talosconfig"
mkdir -p "$here/clusterconfig"
rm -f "$out"
umask 077
talosctl gen config "$CLUSTER_NAME" "$ENDPOINT" \
  --with-secrets <(sops -d "$here/talsecret.sops.yaml") \
  --kubernetes-version "$kv" --talos-version "$tv" \
  --output-types talosconfig -o "$out"

# endpoints/nodes: apid is port 50000, NOT the k8s endpoint.
# Build the arrays plainly — inline command-subst loops die under set -u.
eps=""
nodes=""
for n in "$@"; do
  eps+="${eps:+, }\"https://$n:50000\""
  nodes+="${nodes:+, }\"$n\""
done
yq -i ".contexts.\"$cluster\".endpoints = [$eps] | .contexts.\"$cluster\".nodes = [$nodes]" "$out"

# Re-merging an existing context RENAMES the old one to <cluster>-N junk and may
# move the default — remove the target context first, and restore the previous
# default if the removal took it with us.
cur="$(yq -r '.context // ""' ~/.talos/config 2>/dev/null)"
[[ "$cur" == "$cluster" ]] && cur=""
talosctl config remove -y "$cluster" >/dev/null 2>&1 || true

talosctl config merge "$out"

new_cur="$(yq -r '.context // ""' ~/.talos/config 2>/dev/null)"
if [[ -n "$cur" && "$new_cur" != "$cur" ]]; then
  talosctl config context "$cur"
fi
echo "merged context '$cluster' into ~/.talos/config — pick default explicitly: talosctl config context <name>"
