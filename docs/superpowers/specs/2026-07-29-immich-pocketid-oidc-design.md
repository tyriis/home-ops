# Immich — PocketID OAuth Integration

**Date:** 2026-07-29  
**Status:** Approved  
**Issue:** [#9049](https://github.com/tyriis/home-ops/issues/9049)

## Overview

Integrate Immich's built-in OpenID Connect (OIDC) authentication with the existing PocketID instance at `id.techtales.io`. Users will sign in using their PocketID credentials, with auto-registration and auto-launch enabled.

## Repositories

| Repo | Purpose |
|------|---------|
| `techtales-io/terraform-pocket-id` | Define the OIDC client for PocketID |
| `tyriis/home-ops` | Configure Immich to use the OIDC client |

---

## 1. PocketID OIDC Client

**Repo:** `techtales-io/terraform-pocket-id`  
**File:** `data/clients/immich.yaml`

```yaml
---
apiVersion: terraform.techtales.io/v1alpha1
kind: PocketIdClient
metadata:
  name: immich
spec:
  callbackUrls:
    - https://immich.techtales.io/auth/login
    - https://immich.techtales.io/user-settings
    - app.immich:///oauth-callback
  groups:
    - admins
    - users
  launchUrl: https://immich.techtales.io
```

The Terraform module creates the client in PocketID and stores `CLIENT_ID` and `CLIENT_SECRET` in OpenBao at `infra/pocketid/clients/immich`.

## 2. Manual Credential Sync

After Terraform applies, copy the credentials from the Terraform-managed path to the Immich app's vault path:

| From | To |
|------|-----|
| `infra/pocketid/clients/immich` → `CLIENT_ID` | `infra/kubernetes/main/media/immich` → `IMMICH_OAUTH_CLIENT_ID` |
| `infra/pocketid/clients/immich` → `CLIENT_SECRET` | `infra/kubernetes/main/media/immich` → `IMMICH_OAUTH_CLIENT_SECRET` |

## 3. ExternalSecret — Add OIDC Credentials

**Repo:** `tyriis/home-ops`  
**File:** `kubernetes/main/apps/media/immich/database/external-secret.yaml`

Add to the `immich-env` ExternalSecret template:

```yaml
IMMICH_OAUTH_CLIENT_ID: "{{ .IMMICH_OAUTH_CLIENT_ID }}"
IMMICH_OAUTH_CLIENT_SECRET: "{{ .IMMICH_OAUTH_CLIENT_SECRET }}"
```

These become available to the Immich server container via the existing `envFrom.secretRef` → `immich-env`.

## 4. HelmRelease — OIDC Environment Variables

**Repo:** `tyriis/home-ops`  
**File:** `kubernetes/main/apps/media/immich/app/helm-release.yaml`

Add to the `server` controller's `env:` block:

| Variable | Value | Purpose |
|----------|-------|---------|
| `IMMICH_OAUTH_ENABLED` | `"true"` | Enable OIDC |
| `IMMICH_OAUTH_ISSUER_URL` | `https://id.techtales.io/.well-known/openid-configuration` | PocketID OIDC discovery URL |
| `IMMICH_OAUTH_SCOPE` | `"openid email profile groups"` | Requested scopes |
| `IMMICH_OAUTH_AUTO_REGISTER` | `"true"` | Auto-provision new users |
| `IMMICH_OAUTH_AUTO_LAUNCH` | `"true"` | Skip login page, redirect to PocketID |
| `IMMICH_OAUTH_BUTTON_TEXT` | `"Login with Pocket ID"` | Button label |
| `IMMICH_OAUTH_STORAGE_LABEL_CLAIM` | `preferred_username` | Claim for storage folder naming |
| `IMMICH_OAUTH_END_SESSION_ENDPOINT` | `https://id.techtales.io/api/oidc/end-session` | PocketID logout endpoint |
| `IMMICH_OAUTH_MOBILE_REDIRECT_URI` | `https://immich.techtales.io/api/oauth/mobile-redirect` | Mobile OAuth redirect pass-through |

The `IMMICH_OAUTH_CLIENT_ID` and `IMMICH_OAUTH_CLIENT_SECRET` are injected via the `immich-env` secret.
