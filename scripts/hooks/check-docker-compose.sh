#!/usr/bin/env bash
set -euo pipefail

# Every env_file in the tree resolves through ${SOPS_ENV_FILE:-sops.env}: on the
# hosts that file is SOPS-encrypted, and in a fresh clone it is absent. Pinning the
# indirection at /dev/null satisfies it with no secret while compose still stats
# every env_file target, so a typo'd path fails. The stubs cover ${VAR:?} guards.
export SOPS_ENV_FILE="/dev/null"
export ACME_EMAIL="ci@example.invalid"
export TLS_DOMAIN="example.com"
export MANAGER_API_URL="http://stub.invalid"
export HINDSIGHT_API_LLM_PROVIDER="stub"
export HINDSIGHT_API_LLM_MODEL="stub"
export HINDSIGHT_API_LLM_BASE_URL="http://stub.invalid"
export HINDSIGHT_API_TENANT_EXTENSION="stub"

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose not found" >&2
  exit 1
fi

if (($# > 0)); then
  files=("$@")
else
  mapfile -t files < <(find docker -type f -name compose.yaml | sort)
fi

compose_failed=0
for file in "${files[@]}"; do
  if output="$(docker compose -f "${file}" config -q 2>&1)"; then
    printf 'ok %s\n' "${file}"
  else
    printf 'fail %s\n' "${file}"
    # compose is chatty on failure; the last line carries the actual cause.
    printf '  %s\n' "$(printf '%s\n' "${output}" | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
    compose_failed=$((compose_failed + 1))
  fi
done

# doco-cd deploys each document of these multi-document files as its own stack, so
# a stale working_dir or env_files entry only surfaces in one host's deploy log.
python3 - <<'PY' || doco_failed=1
import glob
import os
import sys

import yaml

checked = 0
failed = 0
for path in sorted(glob.glob("docker/.doco-cd.*.yaml")):
    checked += 1
    errors = []
    with open(path, encoding="utf-8") as handle:
        for doc in yaml.safe_load_all(handle):
            if not doc:
                continue
            name = doc.get("name", "<unnamed>")
            working_dir = doc.get("working_dir") or ""
            if not os.path.isdir(working_dir):
                errors.append(f"{name}: working_dir not found: {working_dir}")
                continue
            if not os.path.isfile(os.path.join(working_dir, "compose.yaml")):
                errors.append(f"{name}: no compose.yaml in {working_dir}")
            for env_file in doc.get("env_files") or []:
                target = os.path.join(working_dir, env_file)
                if not os.path.isfile(target):
                    errors.append(f"{name}: env_files entry not found: {target}")
    if errors:
        failed += 1
        for error in errors:
            print(f"fail {path} (doco-cd): {error}")
    else:
        print(f"ok {path} (doco-cd)")
if checked == 0:
    print("doco-cd: no docker/.doco-cd.*.yaml found; run from the repository root")
    sys.exit(1)
print(f"doco-cd: {checked} checked, {failed} failed")
sys.exit(1 if failed else 0)
PY
doco_failed=${doco_failed:-0}

printf '%s validated, %s failed\n' "${#files[@]}" "${compose_failed}"

if ((compose_failed > 0 || doco_failed > 0)); then
  exit 1
fi
