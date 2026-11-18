#!/usr/bin/env bash
# nixos/ hosts mount every subvolume explicitly (-o subvolid=5 or subvol=).
# `btrfs subvolume set-default` silently rewrites the meaning of every
# cmdline that asks for nothing — it destroys the old-generation rollback
# lane without a sound. 2026-11-16 spec, escape-lane integrity invariant.
set -euo pipefail
fail=0
for f in "$@"; do
  if grep -nE 'set-default' "$f"; then
    echo "  ^ forbidden in $f — mount subvolumes explicitly instead" >&2
    fail=1
  fi
done
exit $fail
