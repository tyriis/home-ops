#!/bin/bash

ALLOWLIST_FILE="/etc/atlantis/allowlist.txt"

if [ ! -f "$ALLOWLIST_FILE" ]; then
  echo "Nobody is allowed to run atlantis (missing allowlist)."
  exit 1
fi

if grep -Fxq "$USER_NAME" "$ALLOWLIST_FILE"
then
  echo "$USER_NAME is allowed to run atlantis."
  exit 0
else
  echo "$USER_NAME is not allowed to run atlantis."
  exit 1
fi
