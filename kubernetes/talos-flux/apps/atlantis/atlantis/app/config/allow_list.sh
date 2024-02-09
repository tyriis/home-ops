#!/bin/bash

if grep -Fxq "$USER_NAME" /home/atlantis/.config/allowlist/orgAllowlist.txt
then
    exit 0
else
    echo "$USER_NAME is not allowed to run atlantis."
    exit 1
fi
