#!/usr/bin/env bash
set -euo pipefail

# Guard: destinationPath (barman cloud plugin ObjectStore) must not end in '/'.
#
# Why: when it does, barman-cloud builds a ListObjectsV2 prefix containing a
# double slash (empty path segment). MinIO validates prefixes as object names
# and rejects it with XMinioInvalidObjectName, so backup retention silently
# never runs and the bucket grows unbounded. See tyriis/home-ops#10860.
#
# Matches: destinationPath: s3://bucket/prefix/   (with or without quotes,
# an optional trailing comment is tolerated)

status=0
for f in "$@"; do
  while IFS= read -r line; do
    echo "${f}: ${line}"
    status=1
  done < <(
    grep -nE '^[[:space:]]*destinationPath:[[:space:]]*"?[^"[:space:]]*/"?([[:space:]]+#.*)?$' "$f" || true
  )
done

if [[ "${status}" -ne 0 ]]; then
  echo "destinationPath values must not end with '/' (breaks barman retention on MinIO, see #10860)" >&2
fi

exit "${status}"
