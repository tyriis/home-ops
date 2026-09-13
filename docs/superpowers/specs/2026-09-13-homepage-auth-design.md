# Homepage OIDC Authentication

- **Date:** 2026-09-13
- **Status:** Accepted (pending implementation)
- **App:** `kubernetes/main/apps/default/homepage`
- **Hostname:** `home.techtales.io`

## Context

[Homepage](https://gethomepage.dev) is deployed via the `bjw-s-labs/app-template`
chart (`5.1.0`) with the official `ghcr.io/gethomepage/homepage` image. As of
v2.0.0 Homepage ships a built-in, opt-in authentication system (password **or**
generic OIDC). The image was bumped to `v2.2.0` by Renovate PR #10026, which is
already merged to `main`.

Currently `home.techtales.io` is served with **no authentication at all** — the
Envoy Gateway `HTTPRoute` has no `SecurityPolicy`, and the app has no auth
configured.

The repository already authenticates six other apps at the gateway via the shared
`components/envoy-pocketid` component (Pocket ID OIDC `SecurityPolicy`). Homepage
does **not** use that component.

The self-hosted OIDC provider is **Pocket ID** at `https://id.techtales.io`
(running `v2.14.0`, SQLite + Litestream, configured through its web UI).

## Decision

Enable Homepage's **native OIDC authentication**, backed by Pocket ID, and
restrict access to the existing Pocket ID **`users`** group.

Access control is enforced by Pocket ID's per-client **Allowed User Groups**
feature. Homepage applies no authorization of its own — it admits any identity
the OIDC client authorizes (documented behaviour: *"Homepage does not apply
additional claim-based authorization"*).

### Why native OIDC rather than the `envoy-pocketid` gateway component

- Homepage v2 has first-class OIDC support; enabling it is config-only.
- It provides an in-app sign-in page and sign-out button, and keeps working
  regardless of which route reaches the app.
- The gateway component applies `SecurityPolicy` to an `HTTPRoute` named after
  `${APP}` and derives the redirect URL as `https://${APP}.techtales.io/...`,
  which does not match `home.techtales.io` and would require a patch.
- Running both would cause double sign-in, so exactly one layer is used.

## Architecture & data flow

```
Browser
  └─ https://home.techtales.io  → Envoy Gateway (no gateway auth)
       └─ homepage pod :3000 (native auth enabled)
            ├─ no session        → /auth/signin
            │                        └─ redirect → https://id.techtales.io  (Pocket ID)
            │                             └─ Pocket ID checks client "Homepage"
            │                                  ├─ user in `users` group  → callback
            │                                  └─ else                    → access_denied
            ├─ callback: /api/auth/callback/homepage-oidc
            └─ session cookie (JWT, signed with HOMEPAGE_AUTH_SECRET) → dashboard
```

Authorization happens **only** at Pocket ID (per-client allowed user groups).
Homepage is a single global gate: authenticated → full dashboard.

## Components & interfaces

### 1. Pocket ID OIDC client (external, manual)

| Setting         | Value                                                        |
| --------------- | ------------------------------------------------------------ |
| Name            | `Homepage`                                                   |
| Public Client   | **off** (confidential → client secret)                       |
| Callback URL    | `https://home.techtales.io/api/auth/callback/homepage-oidc`  |
| Allowed groups  | `users`                                                      |

> Pocket ID ≥ v2.0.0 creates clients **restricted with zero groups**; the `users`
> group must be explicitly selected or logins fail with *"You are not allowed to
> access this service."* Pocket ID v2.14.0 is installed, which includes the
> refresh-token group-enforcement fix (≥ v2.6.0).

### 2. OpenBao secret (external, manual)

Path `infra/kubernetes/main/default/homepage`, keys consumed by the ExternalSecret:

| Key                         | Value / note                                         |
| --------------------------- | ---------------------------------------------------- |
| `HOMEPAGE_AUTH_SECRET`      | `openssl rand -base64 32`, ≥ 32 chars                |
| `HOMEPAGE_OIDC_ISSUER`      | `https://id.techtales.io`                            |
| `HOMEPAGE_OIDC_CLIENT_ID`   | from Pocket ID client                                |
| `HOMEPAGE_OIDC_CLIENT_SECRET` | from Pocket ID client                              |

### 3. Kubernetes ExternalSecret

`app/external-secret.yaml` (already exists, untracked) creates Secret
`homepage-env` from `ClusterSecretStore openbao-backend`, templating the four
keys above. Reused as-is.

### 4. HelmRelease environment

`app/helm-release.yaml` consumes the secret and enables auth:

```yaml
env:
  HOMEPAGE_ALLOWED_HOSTS: home.techtales.io   # existing
  LOG_TARGETS: stdout                          # existing
  HOMEPAGE_AUTH_ENABLED: "true"                # new
  HOMEPAGE_EXTERNAL_URL: https://home.techtales.io  # new
envFrom:
  - secretRef:
      name: homepage-env
```

`HOMEPAGE_AUTH_PASSWORD` is intentionally **not** set (OIDC overrides password
mode). `HOMEPAGE_OIDC_SCOPE` is left at its default (`openid email profile`).

## Repository changes

| File                        | Change                                                            |
| --------------------------- | ----------------------------------------------------------------- |
| `app/external-secret.yaml`  | track existing file (already present, untracked)                  |
| `app/kustomization.yaml`    | add `./external-secret.yaml` to `resources`                       |
| `app/helm-release.yaml`     | add `envFrom` + `HOMEPAGE_AUTH_ENABLED` + `HOMEPAGE_EXTERNAL_URL` |

## Verification

1. Flux reconciles: Kustomization `Ready`, HelmRelease `Ready`, ExternalSecret
   `SecretSynced`, pod `Running`.
2. `curl -s -o /dev/null -w '%{http_code}' https://home.techtales.io/api/healthcheck`
   returns `200` **unauthenticated** (`/api/healthcheck` is allowlisted).
3. Incognito → `https://home.techtales.io` → redirected to Pocket ID → sign in as
   a `users`-group member → dashboard renders and widget tiles load.
4. Negative: an identity **not** in `users` → Pocket ID shows
   *"You are not allowed to access this service."*
5. Sign-out button returns to the sign-in page and the session is cleared.

## Risks & rollback

- **Unauthenticated API consumers break.** Every `/api` route except
  `/api/healthcheck` and `/api/config/custom.css` requires a session once auth is
  on, and Homepage offers no configurable endpoint allowlist. Confirm no script,
  uptime monitor, or dashboard scrapes Homepage's API before enabling.
- **Secret key mismatch** between OpenBao and the ExternalSecret template will
  fail the sync — verify key names exactly.
- **Rollback:** set `HOMEPAGE_AUTH_ENABLED: "false"` (or remove the `envFrom`)
  and let Flux reconcile; no data migration is involved. Rotating
  `HOMEPAGE_AUTH_SECRET` invalidates existing sessions.
- No app-level password rate limiting exists; since password mode is disabled this
  is not applicable, but Envoy-level rate limiting on `/api/auth/*` remains a
  future hardening option.

## Out of scope

- Per-user dashboards, groups, or per-service authorization (not supported by
  Homepage).
- Gateway-level `envoy-pocketid` auth for Homepage (deliberately not used).
- Homepage MCP (`HOMEPAGE_MCP_ENABLED`) and its token.
- The unrelated, uncommitted local modification to `components/envoy-pocketid`
  (affects six other apps); left untouched.

## Follow-up

Pocket ID provisioning is currently **broken** in the `techtales-io/terraform-pocket-id`
Atlantis pipeline. The OIDC client and secret were therefore created manually.
A tracking issue will be filed so the manual client can later be imported into
Terraform.
