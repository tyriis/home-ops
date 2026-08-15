# Unsloth on red (doco-cd) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the Unsloth LLM fine-tuning toolkit (Studio UI + OpenAI/Anthropic API on port 8000, Jupyter on 8888) on the "red" desktop workstation via the doco-cd GitOps-for-Docker system, with SOPS-encrypted passwords.

**Architecture:** A new doco-cd workload is defined per-target under `docker/red/unsloth/` (compose.yaml + sops.env + .env) following the busybox-enc pattern, with a non-deployed shared reference compose under `docker/deploy/unsloth/`. doco-cd polls the git repo every 180s, decrypts `sops.env` via its age key, and runs the compose project with NVIDIA GPU passthrough. The image is digest-pinned and Renovate-managed like ollama/comfyui.

**Tech Stack:** Docker Compose, doco-cd, SOPS (age), NVIDIA container runtime, Renovate, pre-commit/yamllint/markdownlint.

**Spec:** `docs/superpowers/specs/2026-08-16-unsloth-doco-cd-design.md`

---

## Context for the implementer

- doco-cd workload config: `docker/.doco-cd.red.yaml` (entries separated by `---`).
- Reference patterns (read these first): `docker/red/busybox-enc/` (target instance + sops.env), `docker/deploy/busybox-enc/README.md` (docs style), `docker/deploy/ollama/compose.yaml` (NVIDIA GPU pattern, digest-pinned image).
- `.sops.yaml` already contains creation rule `docker/red/.*/sops\.env$` with the red age public key — NO .sops.yaml changes needed.
- SOPS binary: managed via mise (`aqua:getsops/sops` = 3.13.3). Use `mise x sops -- <cmd>` if `sops` is not on PATH.
- yamllint requires `---` document start on every YAML file (`.yamllint.yaml` `document-start: present`).
- The user's age private key is on the red host / user workstation — a subagent CANNOT decrypt sops.env. Implementer verifies encryption succeeded (file contains `ENC[AES256_GCM,...]` lines), and the USER runs the final `sops --decrypt` check.
- The plan's spec is already committed on branch `feature/unsloth-doco-cd`; implementation happens on that branch.
- The implementer is authorized and expected to add any type hints, docstrings, lint suppressions, or repo config updates needed to pass CI/linters for the files in this plan.

## File Structure

| File | Responsibility |
|---|---|
| `docker/deploy/unsloth/compose.yaml` | Shared reference compose (NOT deployed) — blueprint for other targets |
| `docker/red/unsloth/compose.yaml` | Deployed target instance (full copy of shared, busybox-enc style) |
| `docker/red/unsloth/sops.env` | SOPS-encrypted dotenv: JUPYTER_PASSWORD, USER_PASSWORD, UNSLOTH_STUDIO_PASSWORD |
| `docker/red/unsloth/.env` | `TARGET=red` |
| `docker/.doco-cd.red.yaml` | Appended workload entry for unsloth |
| `docker/deploy/unsloth/README.md` | Workload documentation (busybox-enc README style) |

### Task 1: Resolve and pin the Unsloth image tag + digest

**Files:** none (research step)

- [ ] **Step 1: Query current Docker Hub tags for unsloth/unsloth**

Run:
```bash
curl -s 'https://hub.docker.com/v2/repositories/unsloth/unsloth/tags?page_size=100&ordering=last_updated' | jq -r '.results[].name' | head -20
```
Expected: a list of tags. The newest tag contains `-studio-` (e.g. `2026.5.9-pt2.10.0-vllm-0.16.0-cu12.8-studio-release-v0.1.43-beta-2026-MAY-31`). Pick the newest `-studio-` tag — that is the `<STUDIO_TAG>` used below.

- [ ] **Step 2: Resolve the digest for that tag**

Run:
```bash
docker pull unsloth/unsloth:<STUDIO_TAG> && docker inspect --format '{{index .RepoDigests 0}}' unsloth/unsloth:<STUDIO_TAG>
```
Expected: `<STUDIO_TAG>@sha256:<DIGEST>` (e.g. `@sha256:9f4a1f...`). Record the full `<STUDIO_TAG>@sha256:<DIGEST>` — it is used verbatim in Tasks 2 and 3.

If Docker is not available on the machine, use skopeo or crane instead, e.g. `crane digest unsloth/unsloth:<STUDIO_TAG>` (returns just the sha256). Record it.

### Task 2: Create the shared reference compose

**Files:**
- Create: `docker/deploy/unsloth/compose.yaml`

- [ ] **Step 1: Write `docker/deploy/unsloth/compose.yaml`**

Content (replace `<STUDIO_TAG>@sha256:<DIGEST>` with the value from Task 1):

```yaml
---
volumes:
  workspace:
    external: false
    name: unsloth_workspace
    driver: local

services:
  unsloth:
    scale: 1 # scale to 0 if you want to stop the service without losing data
    container_name: unsloth
    image: unsloth/unsloth:<STUDIO_TAG>@sha256:<DIGEST>
    env_file:
      - ${SOPS_ENV_FILE:-sops.env}
    environment:
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: all
      # HF_TOKEN=${HF_TOKEN} # uncomment and add HF_TOKEN to sops.env to pull gated models
    ports:
      - 8000:8000 # Studio UI + OpenAI/Anthropic API (all interfaces)
      - "127.0.0.1:8888:8888" # Jupyter Lab (localhost only)
    restart: unless-stopped
    volumes:
      - workspace:/workspace
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

- [ ] **Step 2: Lint the file**

Run: `yamllint docker/deploy/unsloth/compose.yaml`
Expected: no errors (line-length is warning-level, max 120).

### Task 3: Create the deployed target instance

**Files:**
- Create: `docker/red/unsloth/compose.yaml`

- [ ] **Step 1: Write `docker/red/unsloth/compose.yaml`**

Copy the EXACT content from Task 2 Step 1 (same image, same env_file, same volume). This is the file doco-cd actually deploys.

- [ ] **Step 2: Lint the file**

Run: `yamllint docker/red/unsloth/compose.yaml`
Expected: no errors.

### Task 4: Create the SOPS-encrypted secrets

**Files:**
- Create: `docker/red/unsloth/sops.env` (encrypted)

- [ ] **Step 1: Generate random passwords and write a plaintext temp file**

Run:
```bash
mkdir -p docker/red/unsloth
cat > /tmp/unsloth-sops.env <<EOF
JUPYTER_PASSWORD=$(openssl rand -base64 24)
USER_PASSWORD=$(openssl rand -base64 24)
UNSLOTH_STUDIO_PASSWORD=$(openssl rand -base64 24)
EOF
```
IMPORTANT: this plaintext file must NEVER be committed. It lives in /tmp only.

- [ ] **Step 2: Encrypt in place with SOPS**

Run:
```bash
mise x sops -- --encrypt --in-place --input-type dotenv --output-type dotenv /tmp/unsloth-sops.env
```
(If `sops` is directly on PATH: `sops --encrypt --in-place --input-type dotenv --output-type dotenv /tmp/unsloth-sops.env`)

Then move it into place: `mv /tmp/unsloth-sops.env docker/red/unsloth/sops.env`

- [ ] **Step 3: Verify encryption succeeded**

Run: `rg -c 'ENC\[AES256_GCM' docker/red/unsloth/sops.env`
Expected: output `3` (one per secret value). Also confirm the file ends with the `sops_*` metadata lines (recipient `age16pcjw9...`, version).

NOTE: do NOT run `sops --decrypt` on it — your session lacks the age private key. The user verifies decryption after the branch is pushed (see Verification).

- [ ] **Step 4: Confirm no plaintext leaked**

Run: `git status --porcelain` and visually confirm no `/tmp` file or plaintext `sops.env` is tracked/staged.

### Task 5: Create the .env for the target

**Files:**
- Create: `docker/red/unsloth/.env`

- [ ] **Step 1: Write `docker/red/unsloth/.env`**

Content:
```
TARGET=red
```

### Task 6: Wire the workload into doco-cd

**Files:**
- Modify: `docker/.doco-cd.red.yaml` (append)

- [ ] **Step 1: Append the workload entry**

Append to the end of `docker/.doco-cd.red.yaml`:
```yaml
---
name: unsloth
working_dir: docker/red/unsloth
env_files:
  - .env
```
Do not modify existing entries.

- [ ] **Step 2: Lint the file**

Run: `yamllint docker/.doco-cd.red.yaml`
Expected: no errors.

### Task 7: Write the workload README

**Files:**
- Create: `docker/deploy/unsloth/README.md`

- [ ] **Step 1: Write `docker/deploy/unsloth/README.md`**

Content:

```markdown
# unsloth

Unsloth — LLM fine-tuning toolkit with Unsloth Studio (web UI + OpenAI/Anthropic-compatible API) and Jupyter Lab, running on the NVIDIA GPU of the target host.

## Layout

- `compose.yaml`: shared compose definition (uses `SOPS_ENV_FILE`, default `sops.env`)
- `docker/red/unsloth/compose.yaml`: red target instance
- `docker/red/unsloth/sops.env`: red encrypted dotenv (JUPYTER_PASSWORD, USER_PASSWORD, UNSLOTH_STUDIO_PASSWORD)
- `docker/red/unsloth/.env`: target identifier

## Ports

- `8000`: Unsloth Studio UI + API — bound on all interfaces (LAN).
- `8888`: Jupyter Lab — bound to `127.0.0.1` only.

## Secrets

Passwords are stored in the target's SOPS-encrypted `sops.env`:

- `JUPYTER_PASSWORD` — Jupyter Lab login.
- `USER_PASSWORD` — sudo inside the container.
- `UNSLOTH_STUDIO_PASSWORD` — Studio admin password (avoids interactive first-run bootstrap).

## Manual decrypt check

```bash
sops --decrypt docker/red/unsloth/sops.env
```

## Runtime requirement on doco-cd host

- `doco-cd` must have a valid age private key configured via `SOPS_AGE_KEY_FILE` (or `SOPS_AGE_KEY`).
- NVIDIA driver + nvidia-container-toolkit must be installed; the compose file reserves all GPUs (`driver: nvidia`).

## Notes

- Image is digest-pinned and managed by Renovate.
- RTX 2060 Super (8 GB VRAM) fits QLoRA fine-tuning up to ~8B models. See ADR 0006.
- vLLM standby is enabled (image default): GPU memory is pre-reserved for the API even when idle.
```

- [ ] **Step 2: Lint the markdown**

Run: `npx markdownlint-cli2 --config .markdownlint.yaml docker/deploy/unsloth/README.md` (or `markdownlint` if configured in this repo)
Expected: no errors.

### Task 8: Full verification

- [ ] **Step 1: Lint all changed YAML**

Run:
```bash
yamllint docker/deploy/unsloth/compose.yaml docker/red/unsloth/compose.yaml docker/.doco-cd.red.yaml
```
Expected: no errors.

- [ ] **Step 2: Run repo pre-commit on changed files**

Run: `pre-commit run --files docker/deploy/unsloth/compose.yaml docker/red/unsloth/compose.yaml docker/red/unsloth/sops.env docker/.doco-cd.red.yaml docker/deploy/unsloth/README.md`
Expected: all hooks pass (gitleaks must NOT flag sops.env — it is encrypted). If a hook fails, fix the file (do not bypass hooks).

- [ ] **Step 3: Confirm the workload wiring**

Run: `git diff -- docker/.doco-cd.red.yaml`
Expected: only the appended `---` + unsloth entry. Confirm `working_dir: docker/red/unsloth` matches the created directory.

### Task 9: Commit

- [ ] **Step 1: Stage only the new files**

Run:
```bash
git add docker/deploy/unsloth/compose.yaml docker/red/unsloth/compose.yaml docker/red/unsloth/sops.env docker/red/unsloth/.env docker/.doco-cd.red.yaml docker/deploy/unsloth/README.md
```
Do NOT stage any other files (there are unrelated envoy-pocketid changes and other untracked docs in the working tree).

- [ ] **Step 2: Verify staged set**

Run: `git status` — confirm ONLY the 6 unsloth files are staged.

- [ ] **Step 3: Commit**

Run: `git commit -m "feat(unsloth): add unsloth workload for red via doco-cd"`
Expected: pre-commit hooks run and pass; commit created.

- [ ] **Step 4: Verify**

Run: `git log --oneline -2` — show the new commit on top of `docs(spec): ...`.

## Rollout / Verification (after push)

1. Push `feature/unsloth-doco-cd` to origin.
2. On the red host (or with the user's age key): `sops --decrypt docker/red/unsloth/sops.env` must print the three passwords.
3. doco-cd on red picks up the workload within 180s — no manual action needed.
4. First pull downloads ~7 GB compressed (13 GiB image); Studio takes a few minutes to come up.
5. Browse `http://192.168.1.22:8000` → Studio login with `UNSLOTH_STUDIO_PASSWORD`. On red, `http://127.0.0.1:8888` → Jupyter with `JUPYTER_PASSWORD`.
6. Inside the container `nvidia-smi` shows the RTX 2060 Super.

## Notes / Caveats

- 8 GB VRAM: QLoRA fine-tuning feasible to ~8B models only (ADR 0006).
- vLLM standby pre-reserves VRAM; set `UNSLOTH_VLLM_STANDBY=0` in the compose `environment` if training headroom is preferred (cold-start latency on API calls).
- olla LLM proxy integration (kubernetes/main/apps/ai/olla) is future work — not in scope.

---
