# Talos OIDC Read-Only Access via Pocket-ID

## Status

Approved

## Goal

Enable read-only `talosctl` access to the main and utility Talos Linux clusters using Pocket-ID as the OIDC identity provider. Users authenticate with their passkeys via Pocket-ID
and receive short-lived Talos client certificates with the `os:reader` role.

## Non-Goals

- Kubernetes API (kubectl) OIDC — not in scope
- Write/admin access to Talos API
- Replacing the existing `os:admin` talosconfig used by administrators

## Architecture

```text
┌─────────────────────┐     OIDC Auth     ┌──────────────────┐
│  Developer Machine  │ ──────────────────→│  Pocket-ID       │
│  (talosctl-oidc     │                    │  id.techtales.io │
│   login)            │                    │  (utility/secops)│
│         │           │                    └──────────────────┘
│         │  POST /exchange (ID token)            │
│         ▼           │                           │
│  ┌─────────────┐    │    Validates token via JWKS│
│  │ talosctl-oidc│   │◄───────────────────────────┘
│  │ server       │   │
│  └──────┬───────┘   │
│         │           │
│         │ Signs client cert with Talos API CA    │
│         ▼           │
│  talosctl → Talos API (192.168.100.x:6443)
│  (ephemeral os:reader cert)
└─────────────────────┘
```

### Key Components

1. **Pocket-ID** — Already deployed at `id.techtales.io` in the utility cluster (`kubernetes/utility/apps/secops/pocket-id/`). A new public OIDC client is created for talosctl.

2. **talosctl-oidc server** — Deployed per cluster as a bjw-s app-template HelmRelease via Flux. Each instance holds its own cluster's Talos API CA certificate + key, signed client certs with `os:reader` role, and serves on port 8443.

3. **Talos API CA** — Extracted from each cluster via `talosctl get osrootsecrets` and stored in OpenBao. Pulled into the pod via ExternalSecret.

4. **Client** — Users install the `talosctl-oidc` CLI binary and run `talosctl-oidc login` pointing to the appropriate cluster's server.

## Deployment Layout

### Per cluster (main + utility)

```text
kubernetes/{cluster}/apps/secops/talosctl-oidc/
├── app/
│   ├── kustomization.yaml
│   ├── helm-release.yaml       # bjw-s app-template
│   └── external-secret.yaml    # Talos API CA from OpenBao
└── flux-sync.yaml
```

### bjw-s app-template values

| Field        | Value                                              |
| ------------ | -------------------------------------------------- |
| Image        | `ghcr.io/qjoly/talosctl-oidc-server`               |
| Command      | `["/talosctl-oidc", "serve"]`                      |
| Port         | 8443                                               |
| Service type | LoadBalancer (Cilium IP pool: 192.168.100.200-250) |
| Persistence  | emptyDir for `/data` (TLS cert stability)          |

### Environment variables

| Variable                   | Value (main)                                      | Value (utility)           |
| -------------------------- | ------------------------------------------------- | ------------------------- |
| `TALOSCTL_OIDC_CA_CERT`    | `/config/ca.crt`                                  | `/config/ca.crt`          |
| `TALOSCTL_OIDC_CA_KEY`     | `/config/ca.key`                                  | `/config/ca.key`          |
| `TALOSCTL_OIDC_ISSUER_URL` | `https://id.techtales.io`                         | `https://id.techtales.io` |
| `TALOSCTL_OIDC_CLIENT_ID`  | `<pocketid-client-id>`                            | `<pocketid-client-id>`    |
| `TALOSCTL_OIDC_ENDPOINTS`  | `192.168.100.101,192.168.100.102,192.168.100.103` | `192.168.100.31`          |
| `TALOSCTL_OIDC_CERT_TTL`   | `60m`                                             | `60m`                     |
| `TALOSCTL_OIDC_ROLES`      | `os:reader`                                       | `os:reader`               |
| `TALOSCTL_OIDC_LISTEN`     | `:8443`                                           | `:8443`                   |
| `TALOSCTL_OIDC_DATA_DIR`   | `/data`                                           | `/data`                   |

### Pocket-ID client configuration

| Setting      | Value                                          |
| ------------ | ---------------------------------------------- |
| Client type  | Public                                         |
| Grant type   | Authorization Code                             |
| Redirect URI | `http://127.0.0.1:8900/callback`               |
| Scopes       | `openid`, `profile`, `email`, `offline_access` |
| PKCE         | Enabled (S256)                                 |

### OpenBao secret paths

- Main cluster: `infra/kubernetes/main/secops/talosctl-oidc` (fields: `ca.crt`, `ca.key`)
- Utility cluster: `infra/kubernetes/utility/secops/talosctl-oidc` (fields: `ca.crt`, `ca.key`)

## Implementation Steps

### Phase 1: Prerequisites (manual)

1. Create OIDC client in Pocket-ID admin UI for talosctl
2. Extract Talos API CA from main cluster: `talosctl get osrootsecrets -o yaml` → decode and store
3. Extract Talos API CA from utility cluster: same command
4. Write both CAs to OpenBao under the paths above

### Phase 2: Utility cluster deployment (via Flux)

1. Create directory `kubernetes/utility/apps/secops/talosctl-oidc/app/`
2. Write external-secret.yaml (pulls CA from OpenBao)
3. Write helm-release.yaml (bjw-s app-template config)
4. Write kustomization.yaml
5. Write flux-sync.yaml
6. Register in `kubernetes/utility/apps/secops/kustomization.yaml`

### Phase 3: Main cluster deployment (via Flux)

1. Repeat steps 5-10 for `kubernetes/main/apps/secops/talosctl-oidc/`

### Phase 4: Client setup

1. Install `talosctl-oidc` CLI on developer machines
2. Retrieve server CA from `/ca` endpoint
3. Run `talosctl-oidc login` with appropriate server address

## Failure Mode

If Pocket-ID is down:

- Users with active, unexpired Talos client certs continue working
- New logins / cert renewals fail until Pocket-ID returns
- Admin `os:admin` talosconfig is unaffected

## Security Considerations

- Talos API CA private key is stored in OpenBao and never committed to git
- Client certificates are short-lived (60min default)
- OIDC tokens not cached on disk by the server — validated fresh on each exchange
- Rate limiting and IP allowlist can be configured if needed
