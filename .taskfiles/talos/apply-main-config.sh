#!/usr/bin/env bash
# Diff the rendered main-cluster config against the live one on a node,
# show it, ask for confirmation, then apply — all from memory.
# usage: apply-main-config.sh <talosNN> <ip>
set -euo pipefail

node="${1:?usage: apply-main-config.sh <talosNN> <ip> [--diff-only]}"
ip="${2:?usage: apply-main-config.sh <talosNN> <ip> [--diff-only]}"
diff_only="${3:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d /dev/shm/talos-apply.XXXXXX)"   # tmpfs: RAM only, never disk
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

echo "==> rendering $node" >&2
"$root/talos/render-main-config.sh" "$node" > "$tmp/render.yaml"

echo "==> fetching live config from $ip" >&2
talosctl --talosconfig "$root/../talos/main/clusterconfig/talosconfig" \
  get machineconfig -o json --nodes "$ip" \
  | yq -p json -r '.spec' | yq -p yaml -o yaml '.' > "$tmp/live.yaml"

yq ea -o json -I=0 '.' "$tmp/render.yaml" > "$tmp/render.jsonl"
yq ea -o json -I=0 '.' "$tmp/live.yaml"    > "$tmp/live.jsonl"

echo "==> validating rendered config" >&2
talosctl validate -m metal -c "$tmp/render.yaml"

echo "==> diff live($ip) vs rendered($node)"
echo "    (no output below = configs are identical)"
python3 "$root/talos/diff-live-config.py" "$tmp/live.jsonl" "$tmp/render.jsonl" || true

[[ "$diff_only" == "--diff-only" ]] && exit 0

echo
read -r -p "Apply rendered config to $ip? [y/N] " answer
[[ "${answer,,}" == "y" ]] || { echo "aborted."; exit 1; }

talosctl --talosconfig "$root/../talos/main/clusterconfig/talosconfig" \
  apply-config --nodes "$ip" --file "$tmp/render.yaml"
