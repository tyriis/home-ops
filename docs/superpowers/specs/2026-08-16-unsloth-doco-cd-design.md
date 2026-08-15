# Deploy Unsloth on the Red Host via doco-cd — Design Spec

**Date:** 2026-08-16
**Status:** Proposed

## Overview

Deploy [Unsloth](https://unsloth.ai) — an LLM fine-tuning toolkit bundling
Unsloth Studio (web UI + OpenAI/Anthropic-compatible API), Jupyter Lab, and an
SSH server — on the "red" desktop workstation via the doco-cd GitOps-for-Docker
system. The workload exposes Studio on port 8000 (LAN-reachable) and Jupyter on
port 8888 (localhost-only), persists workspace data to a named Docker volume,
and uses SOPS-encrypted secrets for all passwords.

This spec documents the design in detail. Implementation has not started; an
implementation plan will be written from this spec afterwards.

## Context and Background

### Unsloth

Unsloth is an open-source LLM fine-tuning toolkit (Apache 2.0 for the core
library, AGPL-3.0 for the container and Studio UI). The official Docker image
`unsloth/unsloth` on Docker Hub bundles:

- **Unsloth Studio** — web UI and OpenAI/Anthropic-compatible API server on port
  8000.
- **Jupyter Lab** — notebook environment on port 8888.
- **SSH server** — on port 22 (not exposed in this deployment).

The image is amd64-only, approximately 13 GiB uncompressed (~7 GB compressed
pull), built on CUDA 12.8 and Python 3.12, and runs as a non-root user `unsloth`.

### doco-cd

[doco-cd](https://github.com/kimdre/doco-cd) is the GitOps-for-Docker system
used to manage workloads on non-Kubernetes hosts. It polls the git repository
every 180 seconds, decrypts SOPS-encrypted dotenv files at deploy time, and runs
Docker Compose projects defined by `working_dir` paths relative to `docker/`.
Target hosts are configured via `docker/.doco-cd.<target>.yaml` files.

### Target Host: red

The "red" host is a desktop workstation at `192.168.1.22` with an NVIDIA RTX
2060 Super (8 GB VRAM, CUDA capability 7.5) and 64 GB system RAM. It is a
doco-cd target defined in `docker/.doco-cd.red.yaml`, currently running:

- `busybox-enc` (SOPS validation container)
- `ollama` (local LLM inference)
- `node-exporter` (Prometheus metrics)
- `comfyui` (image generation)

## Goals

- Deploy Unsloth Studio and Jupyter Lab on the red workstation, managed by
  doco-cd with the same GitOps workflow as existing workloads.
- Expose Studio (web UI + API) on port 8000, reachable from the LAN.
- Expose Jupyter Lab on port 8888, reachable from localhost only.
- Persist models, workspace data, and Studio state across container restarts.
- Store all passwords as SOPS-encrypted secrets from day one.
- Follow the established busybox-enc pattern: a shared reference compose under
  `docker/deploy/` alongside the target-specific instance under `docker/red/`.

## Non-Goals

- Exposing the SSH server (port 22) — not needed.
- Reverse proxy or TLS termination in front of the Studio API — direct port
  exposure on the LAN is sufficient for this use case.
- Integration with the olla LLM proxy
  (`kubernetes/main/apps/ai/olla/`) — documented as future work.
- Fine-tuning models larger than ~8B parameters — hardware-constrained by 8 GB
  VRAM (see VRAM Constraints below).
- Multi-GPU or multi-host deployment — single GPU, single host.

## Target Environment

| Property | Value |
|---|---|
| Host | red (desktop workstation) |
| IP | `192.168.1.22` |
| GPU | NVIDIA RTX 2060 Super, 8 GB VRAM, CUDA capability 7.5 |
| RAM | 64 GB |
| OS | Linux (Docker host) |
| doco-cd config | `docker/.doco-cd.red.yaml` |
| SOPS age key | Configured in `.sops.yaml` creation rule `docker/red/.*/sops\.env$` |
| Existing workloads | busybox-enc, ollama, node-exporter, comfyui |

## Decisions

### 1. Interfaces: Studio Web UI + Jupyter only

**Decision:** Expose Studio (port 8000) and Jupyter Lab (port 8888). Do not
expose SSH (port 22).

**Rationale:** Studio provides the primary web UI and API. Jupyter provides
notebook-based access for experimentation. SSH is unnecessary — the host is
already accessible directly, and the container runs a non-root user.

### 2. Networking: Port 8000 on all interfaces, Jupyter on localhost only

**Decision:** Bind port 8000 on all interfaces (`0.0.0.0:8000:8000`) so Studio
UI and API are LAN-reachable at `192.168.1.22:8000`. Bind Jupyter to localhost
only (`127.0.0.1:8888:8888`).

**Rationale:** Studio is the primary interface and should be accessible from
other machines on the LAN (e.g., a laptop browser). Jupyter is a developer tool
that does not need LAN exposure — SSH tunneling or direct host access is
sufficient.

### 3. API exposure: Direct port, no reverse proxy

**Decision:** Expose port 8000 directly. No Caddy or other reverse proxy in
front of the Studio API.

**Rejected alternative:** A Caddy reverse proxy providing TLS termination and
path-based routing. Rejected because:

- The workload is LAN-only; TLS adds complexity without meaningful security
  improvement on a trusted network.
- The Studio API and UI share port 8000 — a proxy would need to handle both,
  adding configuration overhead.
- Simplicity is preferred for a single-user workstation workload. The user
  explicitly rejected the proxy option.

### 4. Storage: Single named Docker volume

**Decision:** A single named volume `unsloth_workspace` mounted at `/workspace`.

**Rationale:** The `/workspace` directory inside the Unsloth container holds:

- `/workspace/.cache/huggingface` — downloaded models and datasets.
- `/workspace/work` — user work (notebooks, scripts, fine-tuning outputs).
- `/workspace/studio` — Studio state.

A named volume persists across container restarts and image updates without
requiring host-path management. A single volume is simpler than splitting into
multiple volumes and matches the container's expectation of a unified workspace.

### 5. Secrets: SOPS-encrypted dotenv with all passwords set from day one

**Decision:** Create `docker/red/unsloth/sops.env` (SOPS-encrypted) containing
`JUPYTER_PASSWORD`, `USER_PASSWORD`, and `UNSLOTH_STUDIO_PASSWORD` — all random
values, all set before first deployment.

**Rejected alternative: Relying on image defaults instead of setting
passwords.** With env vars unset, the container does not auto-generate
passwords. Jupyter falls back to a deterministic default password (`unsloth`),
and Unsloth Studio has no auto-generation: when `UNSLOTH_STUDIO_PASSWORD` is
unset it starts an interactive first-run bootstrap password prompt, and if no
password is ever set it shuts down after `UNSLOTH_STUDIO_BOOTSTRAP_TIMEOUT`
(default 1 hour). Rejected because:

- The deterministic defaults are insecure and publicly well-known — relying on
  them would leave the LAN-exposed Studio UI (port 8000) open with a default
  password.
- Studio's interactive bootstrap is unsuitable for a GitOps-managed (doco-cd),
  unattended deployment: the first-run prompt cannot be answered headlessly,
  and the container would shut down after one hour if no password is ever set.
- SOPS-encrypted dotenv is the established pattern (busybox-enc) and provides
  deterministic, version-controlled, recoverable secrets.

The SOPS creation rule `docker/red/.*/sops\.env$` in `.sops.yaml` already covers
the path `docker/red/unsloth/sops.env` — no `.sops.yaml` changes are needed.

### 6. vLLM standby: Keep image default

**Decision:** Keep `UNSLOTH_VLLM_STANDBY=1` (the image default). Do not override
it.

**Rationale:** The image sets this by default, which pre-reserves GPU memory for
vLLM inference. Disabling it would save VRAM when not using the API but would
add cold-start latency when the API is first used. The default behavior is
acceptable for a workstation where the GPU is not heavily contended.

### 7. Shared reference compose: Yes (busybox-enc pattern)

**Decision:** Include `docker/deploy/unsloth/compose.yaml` as a non-deployed
shared blueprint, alongside the deployed target instance at
`docker/red/unsloth/compose.yaml`.

**Rationale:** This follows the established busybox-enc pattern exactly:

- `docker/deploy/busybox-enc/compose.yaml` — shared reference (not deployed
  directly).
- `docker/red/busybox-enc/compose.yaml` — target-specific instance (deployed by
  doco-cd).

The shared reference serves as documentation and a template for future targets.
The target-specific instance is what doco-cd actually deploys.

**Rejected alternative: Shared deploy dir without per-target secrets.** Using
only `docker/deploy/unsloth/` as the deployed path (like ollama or comfyui)
would mean no target-specific SOPS secrets. Rejected because:

- Unsloth requires passwords (Jupyter, Studio, sudo) that are target-specific
  secrets — these need SOPS encryption, which requires a target-specific path
  matching the `.sops.yaml` creation rule.
- The busybox-enc pattern exists specifically for workloads that need per-target
  encrypted secrets.

## Implementation Plan

### File 1: `docker/deploy/unsloth/compose.yaml`

Shared reference compose (blueprint, NOT deployed on red).

```yaml
---
services:
  unsloth:
    scale: 1
    container_name: unsloth
    image: unsloth/unsloth:<dated-studio-tag>@sha256:<digest>
    env_file:
      - ${SOPS_ENV_FILE:-sops.env}
    ports:
      - "8000:8000"
      - "127.0.0.1:8888:8888"
    volumes:
      - workspace:/workspace
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
      # - HF_TOKEN=<set-in-sops.env-if-needed>
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  workspace:
    name: unsloth_workspace
    driver: local
```

**Notes:**

- Image tag and digest to be determined at implementation time (latest
  dated-studio tag from Docker Hub, digest-pinned for Renovate management).
- `HF_TOKEN` is commented out as an example — can be added to `sops.env` if
  Hugging Face Hub access is needed for gated models.
- NVIDIA device reservation follows the standard Docker Compose GPU passthrough
  pattern.

### File 2: `docker/red/unsloth/compose.yaml`

Deployed target instance. Same content as the shared reference compose above.
Container name `unsloth`. This is the file doco-cd actually deploys.

### File 3: `docker/red/unsloth/sops.env`

SOPS-encrypted dotenv file. Plaintext content (before encryption):

```dotenv
JUPYTER_PASSWORD=<random>
USER_PASSWORD=<random>
UNSLOTH_STUDIO_PASSWORD=<random>
```

All three values are random strings generated at implementation time. Encrypted
with the age key configured in `.sops.yaml` for the `docker/red/.*/sops\.env$`
path regex.

### File 4: `docker/red/unsloth/.env`

```dotenv
TARGET=red
```

Matches the busybox-enc pattern — identifies the target for doco-cd.

### File 5: `docker/.doco-cd.red.yaml` (append)

Append a new workload entry to the existing file:

```yaml
---
name: unsloth
working_dir: docker/red/unsloth
env_files:
  - .env
```

This tells doco-cd to deploy the compose project at `docker/red/unsloth/` with
the `.env` file (which sets `TARGET=red`). doco-cd automatically decrypts
`sops.env` via the `env_file` reference in `compose.yaml`.

### File 6: `docker/deploy/unsloth/README.md`

Workload documentation mirroring the `docker/deploy/busybox-enc/README.md`
style. Contents:

- Purpose: LLM fine-tuning toolkit with Studio web UI and Jupyter Lab.
- Layout: list of files (shared compose, target instances, encrypted secrets).
- Manual decrypt check: `sops --decrypt docker/red/unsloth/sops.env`.
- Runtime requirements: doco-cd with age key, NVIDIA GPU with Docker runtime.
- Ports: 8000 (Studio, all interfaces), 8888 (Jupyter, localhost only).

## Verification

1. **Pre-commit SOPS check:** `sops --decrypt docker/red/unsloth/sops.env`
   succeeds locally, confirming the age key and creation rule are correctly
   wired.
2. **doco-cd pickup:** After push, doco-cd on red picks up the new workload
   automatically on its next 180-second poll cycle. No manual action on the
   host is required.
3. **Image pull:** First deployment pulls approximately 7 GB compressed /
   13 GiB uncompressed. Allow time for the initial download.
4. **Studio access:** Browse to `http://192.168.1.22:8000` — Studio UI should
   load, prompting for `UNSLOTH_STUDIO_PASSWORD`.
5. **Jupyter access:** On the red host, browse to `http://127.0.0.1:8888` —
   Jupyter Lab should load, prompting for `JUPYTER_PASSWORD`.
6. **GPU passthrough:** Inside the container, `nvidia-smi` should show the RTX
   2060 Super with 8 GB VRAM.

## VRAM Constraints

The RTX 2060 Super has 8 GB VRAM. This imposes hard limits on QLoRA
fine-tuning:

| Model size | Approximate VRAM | Feasibility |
|---|---|---|
| 7B | ~5 GB | Comfortable |
| 8B | ~6 GB | Comfortable |
| 14B | ~8.5 GB | Borderline / likely OOM |
| 70B+ | 30+ GB | Not feasible |

These constraints are consistent with the findings documented in
[ADR 0006](../../decisions/0006-local-llm-agentic-coding-not-feasable-on-8gb-vram.md),
which evaluated the RTX 2060 Super's 8 GB VRAM as a hard constraint for local
LLM workloads on this workstation.

The RTX 2060 Super has CUDA capability 7.5 (Turing architecture), which meets
Unsloth's minimum requirement of CUDA capability >= 7.0.

With `UNSLOTH_VLLM_STANDBY=1` (the image default), vLLM pre-reserves GPU memory
for inference, reducing the VRAM available for fine-tuning. If fine-tuning
larger models is needed, setting `UNSLOTH_VLLM_STANDBY=0` in the environment
would free that reservation — at the cost of cold-start latency when the API is
first used.

## Future Work

### olla LLM proxy integration

The olla LLM proxy (`kubernetes/main/apps/ai/olla/app/config/config.yaml`)
currently supports ollama, lm-studio, and llamacpp endpoint types. Unsloth
Studio exposes an OpenAI/Anthropic-compatible API on port 8000, which could be
registered as an olla endpoint — allowing cluster-based applications to route
inference requests to the Unsloth API on the red workstation.

This is not in scope for this deployment. Integration would require:

- Confirming olla supports a generic OpenAI-compatible endpoint type (or adding
  one).
- Network routing from the Kubernetes cluster to `192.168.1.22:8000`.
- Deciding whether fine-tuned models served by Unsloth should appear alongside
  ollama models in the proxy's model list.

### Additional targets

If Unsloth is needed on other doco-cd hosts (e.g., a future workstation with
more VRAM), the shared reference compose at `docker/deploy/unsloth/compose.yaml`
serves as the template — create a new `docker/<target>/unsloth/` directory with
target-specific `compose.yaml`, `sops.env`, and `.env`, and append a workload
entry to the target's `.doco-cd.<target>.yaml`.

## References

- [Unsloth](https://unsloth.ai) — LLM fine-tuning toolkit.
- [Unsloth Docker Hub](https://hub.docker.com/r/unsloth/unsloth) — official
  container image.
- [doco-cd](https://github.com/kimdre/doco-cd) — GitOps-for-Docker system.
- ADR 0006:
  [Local LLM Agentic Coding not feasible on 8 GB VRAM](../../decisions/0006-local-llm-agentic-coding-not-feasable-on-8gb-vram.md)
- Reference pattern: `docker/deploy/busybox-enc/` and `docker/red/busybox-enc/`
  (shared reference + target-specific instance with SOPS secrets).
- SOPS configuration: `.sops.yaml` — creation rule
  `docker/red/.*/sops\.env$`.
- doco-cd target config: `docker/.doco-cd.red.yaml`.
- olla LLM proxy: `kubernetes/main/apps/ai/olla/app/config/config.yaml`.
