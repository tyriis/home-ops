# Hermes WebUI — Design Doc

## Overview

Add [Hermes WebUI](https://github.com/nesquena/hermes-webui) as a sidecar container to each existing hermes-agent pod, providing a web-based chat UI for each agent instance. Uses gateway-backed chat mode, connecting to the agent's API server on localhost.

## Architecture

```
┌─────────────────────────────────────┐
│ hermes-agent-{instance} Pod         │
│                                     │
│ ┌──────────┐  ┌───────────┐         │
│ │ app      │  │ dashboard │         │
│ │ gateway  │  │ (hermes   │         │
│ │ run      │  │  dashboard)│        │
│ │ :8642    │  │ :9119     │         │
│ └────┬─────┘  └───────────┘         │
│      │ localhost:8642               │
│      ▼                              │
│ ┌──────────┐                        │
│ │ webui    │                        │
│ │ server.py│                        │
│ │ :8787    │                        │
│ └──────────┘                        │
│                                     │
│ PVC: /opt/data (shared)             │
│ emptyDir: /tmp, /run (shared)       │
└─────────────────────────────────────┘
         │
         │ HTTPRoute
         ▼
    Envoy Gateway (euphoria/moira/titan-ai/nova.techtales.io)
```

## Auth

- Password auth at bootstrap (`HERMES_WEBUI_PASSWORD` from OpenBao secret)
- WebAuthn passkeys for day-to-day login (registered via Settings → System)
- No OIDC/OAuth2 needed

## Instances & Hostnames

| Instance | Subdomain |
|----------|-----------|
| tyriis | `euphoria.techtales.io` |
| jazzlyn | `moira.techtales.io` |
| crowlex | `titan-ai.techtales.io` |
| techinik | `nova.techtales.io` |

## Container Configuration

Third container in the existing `hermes` controller, alongside `app` and `dashboard`:

| Field | Value |
|-------|-------|
| Image | `ghcr.io/nesquena/hermes-webui:0.51.397` |
| Command | `["python3", "/apptoo/server.py"]` |
| Port | 8787 (TCP) |
| SecurityContext | Same as existing containers: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false` |

### Environment

| Variable | Value |
|----------|-------|
| `HERMES_WEBUI_HOST` | `0.0.0.0` |
| `HERMES_WEBUI_PORT` | `8787` |
| `HERMES_WEBUI_CHAT_BACKEND` | `gateway` |
| `HERMES_WEBUI_GATEWAY_BASE_URL` | `http://localhost:8642` |
| `HOME` | `/opt/data` |
| `HERMES_WEBUI_STATE_DIR` | `/opt/data/webui` |
| `HERMES_WEBUI_PASSWORD` | From ExternalSecret |

### Persistence

Reuses existing pod volumes — no new volumes needed:

| Volume | Mount Path | Purpose |
|--------|------------|---------|
| `data` (PVC) | `/opt/data` | WebUI state, sessions, passkeys |
| `tmp` (emptyDir) | `/tmp` | Temp files |
| `run` (emptyDir) | `/run` | Runtime files |

### Probing

Liveness + readiness probe on `GET /health` port 8787, same pattern as existing containers but with the webui's endpoint.

## Service & Route

- A new service port `webui` (8787) added to the existing `service` block
- A new HTTPRoute per instance, pointing the subdomain to port 8787
- Annotations for external-dns and homepage

## Network Policy

Add ingress rule for port 8787 from `networking` namespace (Envoy gateway):

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: networking
    ports:
      - protocol: TCP
        port: 8787
```

## Directory Structure

Same multi-instance pattern as the existing agent (`flux-sync.yaml` with 4 Kustomization entries, all pointing to shared `app/` directory):

```
kubernetes/main/apps/hermes-agent/hermes-webui/
├── flux-sync.yaml      # 4 Kustomization entries (tyriis, jazzlyn, crowlex, techinik)
└── app/
    ├── kustomization.yaml
    └── helm-release.yaml
```

Or more likely, since it's a sidecar, the webui config lives directly in the existing `app/` directory as additions to `helm-release.yaml`, and the `flux-sync.yaml` is unchanged (it already deploys the app/ directory which contains all three containers).

## OpenBao Secret

The existing ExternalSecret path `infra/kubernetes/main/hermes-agent/${APP}` already exists for the agent. The webui password (`HERMES_WEBUI_PASSWORD`) will be added to this existing secret entry.
