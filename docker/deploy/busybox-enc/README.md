# busybox-enc

This workload is a **debug/test container only** to validate SOPS decryption in `doco-cd`.

It is not intended as an application workload.

## Purpose

- verify target-specific SOPS key wiring
- verify `doco-cd` decrypts dotenv files before compose runtime
- print `DEMO_SECRET` to container logs for quick validation

## Layout

- `compose.yaml`: shared compose definition (uses `SOPS_ENV_FILE`, default `sops.env`)
- `docker/red/busybox-enc/compose.yaml`: red target instance
- `docker/red/busybox-enc/sops.env`: red encrypted dotenv
- `docker/synology/busybox-enc/compose.yaml`: synology target instance
- `docker/synology/busybox-enc/sops.env`: synology encrypted dotenv

## Manual decrypt check

```bash
sops --decrypt docker/red/busybox-enc/sops.env
sops --decrypt docker/synology/busybox-enc/sops.env
```

## Runtime requirement on doco-cd host

`doco-cd` must have a valid age private key configured via:

- `SOPS_AGE_KEY_FILE` (recommended), or
- `SOPS_AGE_KEY`

If the key is missing or wrong, deployment fails during the decryption stage.
