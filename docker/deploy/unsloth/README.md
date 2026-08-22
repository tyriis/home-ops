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
