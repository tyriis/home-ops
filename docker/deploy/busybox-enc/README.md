# busybox-enc

Minimal test workload for doco-cd encrypted dotenv files on the `red` target.

## Files

- `compose.yaml` - runs a busybox container and prints hello + a secret env var
- `secrets.enc.env` - encrypted file consumed by compose

## Verify decryption manually (optional)

```bash
sops --decrypt docker/deploy/busybox-sops/secrets.enc.env
```

## Runtime requirement on doco-cd host

The doco-cd container must have one of these configured:

- `SOPS_AGE_KEY_FILE` (recommended)
- `SOPS_AGE_KEY`

Without the age private key, deployment will fail when doco-cd tries to decrypt `secrets.enc.env`.
