#!/bin/bash

if grep -Fxq "$USER_NAME" /etc/atlantis/allowlist.txt
then
  echo "$USER_NAME is allowed to run atlantis."
  exit 0
else
  echo "$USER_NAME is not allowed to run atlantis."
  exit 1
fi
