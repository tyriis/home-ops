#!/usr/bin/env bash
# Check each committed factory.talos.dev schematic against the installer image refs
# that patches/ actually installs.
# Usage: check-schematic.sh [--online] [cluster ...]   (default: every talos/*/schematic.yaml)
# --online re-derives each id from factory.talos.dev — needs network.
set -euo pipefail
shopt -s nullglob

online=0
clusters=()
for arg in "$@"; do
  case "$arg" in
    --online) online=1 ;;
    "") ;;
    -h | --help)
      sed -n '2,4s/^# \{0,1\}//p' "$0"
      exit 0
      ;;
    *) clusters+=("$arg") ;;
  esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
status=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  status=1
}

if [ "${#clusters[@]}" -eq 0 ]; then
  for schematic in "$root"/talos/*/schematic.yaml; do
    cluster="${schematic#"$root"/talos/}"
    clusters+=("${cluster%/schematic.yaml}")
  done
fi
if [ "${#clusters[@]}" -eq 0 ]; then
  echo "FAIL: no talos/*/schematic.yaml found" >&2
  exit 1
fi

for cluster in "${clusters[@]}"; do
  schematic="$root/talos/$cluster/schematic.yaml"
  if [ ! -f "$schematic" ]; then
    fail "missing $schematic"
    continue
  fi

  id="$(sed -n 's/^# id: \([0-9a-f]\{64\}\)$/\1/p' "$schematic")"
  if [ -z "$id" ]; then
    fail "$schematic: no '# id: <64 hex>' header line"
    continue
  fi

  before="$status"
  found=0
  for patch in "$root/talos/$cluster"/patches/*.patch.yaml; do
    while IFS= read -r image; do
      found=$((found + 1))
      case "$image" in
        *"/metal-installer-secureboot/$id:"*) ;;
        *) fail "talos/$cluster/patches: installer image '$image' does not carry schematic id $id" ;;
      esac
    done < <(yq ea -r 'select(.kind == "UnattendedInstallConfig") | .installer.image // ""' "$patch" |
      sed '/^---$/d; /^$/d')
  done
  if [ "$found" -eq 0 ]; then
    fail "talos/$cluster/patches: no UnattendedInstallConfig installer image refs found"
  fi

  if [ "$online" -eq 1 ] && [ "$status" -eq "$before" ]; then
    if remote="$(curl -fsS -X POST --data-binary "@$schematic" https://factory.talos.dev/schematics |
      yq -p json -r '.id')"; then
      if [ "$remote" != "$id" ]; then
        fail "$schematic: factory.talos.dev returned id '$remote', header says $id"
      fi
    else
      fail "$schematic: factory.talos.dev request failed"
    fi
  fi

  if [ "$status" -eq "$before" ]; then
    printf 'ok: %s %s\n' "$cluster" "$id"
  fi
done

exit "$status"
