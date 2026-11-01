#!/usr/bin/env bash
# Diff a rendered machine config against the live one, show it, ask, then
# apply — all from memory (tmpfs only). Generalizes apply-main-config.sh.
# usage: apply-config.sh <cluster> <node> <ip> [--diff-only]
set -euo pipefail

cluster="${1:?usage: apply-config.sh <cluster> <node> <ip> [--diff-only]}"
node="${2:?usage: apply-config.sh <cluster> <node> <ip> [--diff-only]}"
ip="${3:?usage: apply-config.sh <cluster> <node> <ip> [--diff-only]}"
diff_only="${4:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Every write op must be explicit about context + node — never default context.
[[ -n "${cluster}" && -n "${ip}" ]]

tmp="$(mktemp -d /dev/shm/talos-apply.XXXXXX)"   # tmpfs: RAM only, never disk
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

echo "==> rendering $cluster/$node" >&2
"$root/.taskfiles/talos/render-config.sh" "$cluster" "$node" > "$tmp/render.yaml"

echo "==> fetching live config from $ip" >&2
talosctl --context "$cluster" --nodes "$ip" get machineconfig -o json \
  | yq -p json -r 'select(.metadata.id == "persistent") | .spec' \
  | yq -p yaml -o yaml '.' > "$tmp/live.yaml"

yq ea -o json -I=0 '.' "$tmp/render.yaml" > "$tmp/render.jsonl"
yq ea -o json -I=0 '.' "$tmp/live.yaml"    > "$tmp/live.jsonl"

echo "==> validating rendered config" >&2
talosctl validate -m metal -c "$tmp/render.yaml"

echo "==> diff live($ip) vs rendered($cluster/$node)"
diff_out="$(python3 "$root/.taskfiles/talos/diff-live-config.py" "$tmp/live.jsonl" "$tmp/render.jsonl" || true)"
echo "$diff_out"

[[ "$diff_only" == "--diff-only" ]] && exit 0

if grep -q "configs identical" <<<"$diff_out"; then
  echo "nothing to apply — live config already matches the render. Done."
  exit 0
fi

echo
read -r -p "Apply rendered config to $ip? [y/N] " answer
[[ "${answer,,}" == "y" ]] || { echo "aborted."; exit 1; }

talosctl --context "$cluster" --nodes "$ip" apply-config --file "$tmp/render.yaml"
