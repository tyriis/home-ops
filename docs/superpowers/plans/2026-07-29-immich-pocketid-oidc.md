# Immich PocketID OIDC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Immich to authenticate via PocketID using native OIDC integration.

**Architecture:** Two repos are involved: (1) `techtales-io/terraform-pocket-id` — define the OIDC client in Terraform-managed YAML data, which creates the client in PocketID and stores credentials in OpenBao; (2) `tyriis/home-ops` — add OIDC env vars to Immich's HelmRelease and an ExternalSecret to pull the client credentials. A manual OpenBao credential sync bridges the two.

**Tech Stack:** Terraform (pocketid provider), Flux/HelmRelease (bjw-s app-template), ExternalSecrets Operator, OpenBao, PocketID

---

### Task 1: Create PocketID OIDC client definition

**Repo:** `techtales-io/terraform-pocket-id`  
**File:** Create `data/clients/immich.yaml`

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
  pkce: true
```

- [ ] **Step 1:** Create the file with the content above.
- [ ] **Step 2:** Commit and open a PR.

```bash
git add data/clients/immich.yaml
git commit -m "feat(clients): add immich oidc client #18"
git push origin HEAD
```

- [ ] **Step 3:** Wait for Atlantis to auto-apply the Terraform, creating the client in PocketID and storing `CLIENT_ID`/`CLIENT_SECRET` in OpenBao at `infra/pocketid/clients/immich`.

---

### Task 2: Manual OpenBao credential sync

- [ ] **Step 1:** Read the generated credentials from OpenBao.

```bash
vault kv get -mount=infra pocketid/clients/immich
```

- [ ] **Step 2:** Write them to the Immich app's OpenBao path, preserving all existing keys.

```bash
vault kv patch -mount=infra kubernetes/main/media/immich \
  OAUTH_CLIENT_ID=<value> \
  OAUTH_CLIENT_SECRET=<value> \
  DB_USERNAME=<existing> \
  DB_PASSWORD=<existing> \
  DB_DATABASE_NAME=<existing> \
  AWS_ACCESS_KEY_ID=<existing> \
  AWS_SECRET_ACCESS_KEY=<existing>
```

---

### Task 3: Add OIDC credential mappings to ExternalSecret

**Repo:** `tyriis/home-ops`  
**Branch:** `feature/immich-pocket-id`  
**File:** Modify `kubernetes/main/apps/media/immich/database/external-secret.yaml`

Add two lines to the `immich-env` ExternalSecret template's `data:` block:

```yaml
        IMMICH_OAUTH_CLIENT_ID: "{{ .OAUTH_CLIENT_ID }}"
        IMMICH_OAUTH_CLIENT_SECRET: "{{ .OAUTH_CLIENT_SECRET }}"
```

The relevant section after the change:

```yaml
      data:
        DB_DATABASE_NAME: "{{ .DB_USERNAME }}"
        DB_USERNAME: "{{ .DB_USERNAME }}"
        DB_PASSWORD: "{{ .DB_PASSWORD }}"
        IMMICH_OAUTH_CLIENT_ID: "{{ .OAUTH_CLIENT_ID }}"
        IMMICH_OAUTH_CLIENT_SECRET: "{{ .OAUTH_CLIENT_SECRET }}"
```

- [ ] **Step 1:** Edit the file to add the two new template mappings.
- [ ] **Step 2:** Validate YAML.
- [ ] **Step 3:** Commit.

```bash
git add kubernetes/main/apps/media/immich/database/external-secret.yaml
git commit -m "feat(immich): add oidc credential mappings to external secret #9049"
```

---

### Task 4: Add OIDC env vars to Immich HelmRelease

**Repo:** `tyriis/home-ops`  
**Branch:** `feature/immich-pocket-id`  
**File:** Modify `kubernetes/main/apps/media/immich/app/helm-release.yaml`

Add the following env vars to the `server` controller's `env:` block:

```yaml
              IMMICH_OAUTH_AUTO_LAUNCH: "true"
              IMMICH_OAUTH_AUTO_REGISTER: "true"
              IMMICH_OAUTH_BUTTON_TEXT: "Login with Pocket ID"
              IMMICH_OAUTH_ENABLED: "true"
              IMMICH_OAUTH_ISSUER_URL: https://id.techtales.io/.well-known/openid-configuration
              IMMICH_OAUTH_SCOPE: "openid email profile groups"
              IMMICH_OAUTH_STORAGE_LABEL_CLAIM: preferred_username
              IMMICH_OAUTH_END_SESSION_ENDPOINT: https://id.techtales.io/api/oidc/end-session
              IMMICH_OAUTH_MOBILE_REDIRECT_URI: https://immich.techtales.io/api/oauth/mobile-redirect
```

- [ ] **Step 1:** Edit the file to add the env vars.
- [ ] **Step 2:** Validate YAML.
- [ ] **Step 3:** Commit.

```bash
git add kubernetes/main/apps/media/immich/app/helm-release.yaml
git commit -m "feat(immich): configure oidc env vars for pocketid #9049"
```

---

### Task 5: Verify Flux reconciliation

- [ ] **Step 1:** Push the branch and open a PR.
- [ ] **Step 2:** Verify the `immich-env` secret has the new OIDC keys.
- [ ] **Step 3:** Verify the Immich server pod is running with the new env vars.
- [ ] **Step 4:** Hit `https://immich.techtales.io` and confirm redirect to PocketID login.
