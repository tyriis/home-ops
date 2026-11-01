#!/usr/bin/env bash
# Render a cluster node's config and ask the NODE for its dry-run plan:
# reboot/no-reboot verdict + server-computed, redacted config diff.
# Applies nothing. Render lands in tmpfs only, deleted on exit.
# usage: dry-run-config.sh <cluster> <node> <ip>
set -euo pipefail

cluster="${1:?usage: dry-run-config.sh <cluster> <node> <ip>}"
node="${2:?usage: dry-run-config.sh <cluster> <node> <ip>}"
ip="${3:?usage: dry-run-config.sh <cluster> <node> <ip>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

tmp="$(mktemp -d /dev/shm/talos-dry.XXXXXX)"   # tmpfs: RAM only, never disk
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

"$root/.taskfiles/talos/render-config.sh" "$cluster" "$node" > "$tmp/render.yaml"

# --file - is not supported for stdin on 1.14; the tmpfs file is the supported path.
talosctl --context "$cluster" --nodes "$ip" apply-config --dry-run --file "$tmp/render.yaml"
