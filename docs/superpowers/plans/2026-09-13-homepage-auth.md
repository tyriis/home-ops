# Homepage OIDC Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Protect `home.techtales.io` with Homepage v2's native OIDC login backed by Pocket ID, restricted to the Pocket ID `users` group.

**Architecture:** The `ghcr.io/gethomepage/homepage:v2.2.0` image is already on `main`. Enable auth purely through environment variables on the existing `bjw-s-labs/app-template` HelmRelease, sourcing secrets from an `ExternalSecret` backed by OpenBao. No gateway `SecurityPolicy` is used. Authorization is enforced by Pocket ID's per-client *Allowed User Groups*.

**Tech Stack:** Kubernetes, Flux CD, Kustomize, `bjw-s-labs/app-template` Helm chart, External Secrets Operator, OpenBao, Homepage v2, Pocket ID.

**Spec:** `docs/superpowers/specs/2026-09-13-homepage-auth-design.md`

**Branch:** `feature/homepage-auth` (already created from `main`)

> **Implementer note (repo policy):** You are authorized and expected to add any formatting, lint suppressions, or configuration required to pass the project's linters, type-checkers, and CI. Run `task lint:yaml` / prettier if a step introduces formatting drift, but do not reformat unrelated files.
>
> **Ticket reference:** Commit messages below omit a ticket reference. If a ticket number is known when you commit, append it (`feat(homepage): add auth external secret #123`). Do not invent one.

---

## Pre-flight (external, already completed — verify only)

- [ ] **Step 1: Confirm the image is v2.2.0**

Run: `rg -n "tag: v" kubernetes/main/apps/default/homepage/app/helm-release.yaml`
Expected: `tag: v2.2.0@sha256:753eeb0cc22ab7baad39ed47cbd1aae14e193dd1b264e965f193a9ea1d1e1bdd`

- [ ] **Step 2: Confirm the Pocket ID OIDC client (user)**

In the Pocket ID admin UI (`https://id.techtales.io`), the client **Homepage** must have:
- Public Client = off (confidential)
- Callback URL = `https://home.techtales.io/api/auth/callback/homepage-oidc`
- Allowed User Groups = `users`

- [ ] **Step 3: Confirm the OpenBao secret keys (user)**

Path `infra/kubernetes/main/default/homepage` must contain exactly:
`HOMEPAGE_AUTH_SECRET` (≥ 32 chars), `HOMEPAGE_OIDC_ISSUER`,
`HOMEPAGE_OIDC_CLIENT_ID`, `HOMEPAGE_OIDC_CLIENT_SECRET`.

If a key name differs, STOP and reconcile it with the ExternalSecret template in
Task 1 before proceeding.

---

## Task 1: Track the ExternalSecret and register it in Kustomize

**Files:**
- Add: `kubernetes/main/apps/default/homepage/app/external-secret.yaml` (already exists untracked)
- Modify: `kubernetes/main/apps/default/homepage/app/kustomization.yaml:6-8`

- [ ] **Step 1: Confirm the ExternalSecret content**

Run: `cat kubernetes/main/apps/default/homepage/app/external-secret.yaml`
Expected (exact): an `ExternalSecret` named `homepage-env`, `secretStoreRef` = `openbao-backend` (`ClusterSecretStore`), `target.name` = `homepage-env`, template keys `HOMEPAGE_AUTH_SECRET`, `HOMEPAGE_OIDC_ISSUER`, `HOMEPAGE_OIDC_CLIENT_ID`, `HOMEPAGE_OIDC_CLIENT_SECRET`, and `dataFrom.extract.key: infra/kubernetes/main/${NAMESPACE}/${APP}`. If it differs, fix it to match this before continuing.

- [ ] **Step 2: Register the file in kustomization.yaml**

Replace:
```yaml
resources:
  - ./helm-release.yaml
  - ./rbac.yaml
```
with:
```yaml
resources:
  - ./helm-release.yaml
  - ./rbac.yaml
  - ./external-secret.yaml
```

- [ ] **Step 3: Render the Kustomization to verify it builds and includes the ExternalSecret**

Run:
```bash
kubectl kustomize kubernetes/main/apps/default/homepage/app | rg -n "kind: ExternalSecret" -A2
```
Expected: exit 0 and output containing `kind: ExternalSecret` and `name: homepage-env`.

- [ ] **Step 4: Lint the changed file**

Run:
```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/default/homepage/app/kustomization.yaml kubernetes/main/apps/default/homepage/app/external-secret.yaml
```
Expected: exit 0 (warnings about line length in unrelated repo files are pre-existing and out of scope).

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/default/homepage/app/external-secret.yaml \
        kubernetes/main/apps/default/homepage/app/kustomization.yaml
git commit -m "feat(homepage): add auth external secret"
```

---

## Task 2: Enable OIDC environment on the HelmRelease

**Files:**
- Modify: `kubernetes/main/apps/default/homepage/app/helm-release.yaml:48-51`

- [ ] **Step 1: Add the auth env vars and `envFrom`**

Replace:
```yaml
            env:
              LOG_TARGETS: stdout
              HOMEPAGE_ALLOWED_HOSTS: home.techtales.io
            image:
```
with:
```yaml
            env:
              LOG_TARGETS: stdout
              HOMEPAGE_ALLOWED_HOSTS: home.techtales.io
              HOMEPAGE_AUTH_ENABLED: "true"
              HOMEPAGE_EXTERNAL_URL: https://home.techtales.io
            envFrom:
              - secretRef:
                  name: homepage-env
            image:
```

Leave `HOMEPAGE_AUTH_PASSWORD` unset (OIDC overrides password mode) and do not
set `HOMEPAGE_OIDC_SCOPE` (default `openid email profile` is sufficient).
`HOMEPAGE_AUTH_ENABLED` must be the **string** `"true"` — any other value leaves
auth disabled.

- [ ] **Step 2: Render and assert the values are present**

Run:
```bash
kubectl kustomize kubernetes/main/apps/default/homepage/app | rg -n "HOMEPAGE_AUTH_ENABLED|HOMEPAGE_EXTERNAL_URL|homepage-env" -B1 -A1
```
Expected: exit 0; `HOMEPAGE_AUTH_ENABLED: "true"`, `HOMEPAGE_EXTERNAL_URL: https://home.techtales.io`, and a `secretRef` referencing `homepage-env`.

- [ ] **Step 3: Lint the changed file**

Run:
```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/default/homepage/app/helm-release.yaml
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/default/homepage/app/helm-release.yaml
git commit -m "feat(homepage): enable homepage oidc auth"
```

---

## Task 3: Push branch and open the PR

**Files:** none

- [ ] **Step 1: Push the branch**

Run:
```bash
git push -u origin feature/homepage-auth
```
Expected: branch published, upstream tracking set.

- [ ] **Step 2: Present commits and confirm before opening the PR**

Run `git log --oneline main..HEAD` and show the commits to the user. Per repo
policy, **do not create a PR without confirmation**. Ask: "Ready for a PR?"

- [ ] **Step 3: Create the PR (after confirmation)**

Run:
```bash
gh pr create --repo tyriis/home-ops --base main --head feature/homepage-auth \
  --title "feat(homepage): enable oidc auth" \
  --body "Enables Homepage v2 native OIDC auth against Pocket ID, restricted to the Pocket ID \`users\` group. Spec: docs/superpowers/specs/2026-09-13-homepage-auth-design.md"
```
Expected: PR URL printed. Report it to the user.

- [ ] **Step 4: Merge (only when instructed)**

Run:
```bash
task git:pr-merge -- <PR_NUMBER>
```
NEVER use `gh pr merge --squash`; squash is forbidden in this repo.

---

## Task 4: File the provisioning follow-up ticket

**Files:** none

- [ ] **Step 1: Create the issue**

Run:
```bash
gh issue create --repo tyriis/home-ops \
  --title "fix(atlantis): Pocket ID provisioning is broken" \
  --body "The techtales-io/terraform-pocket-id Atlantis pipeline is currently broken, so the Homepage OIDC client and its OpenBao secret were created manually (see docs/superpowers/specs/2026-09-13-homepage-auth-design.md). Restore provisioning and import the manual Homepage client so it is declared in Terraform."
```
Expected: issue URL printed. Report it to the user.

- [ ] **Step 2: Confirm the target repo with the user**

If the user prefers the ticket in `techtales-io/terraform-pocket-id` instead,
re-run Step 1 with `--repo techtales-io/terraform-pocket-id`.

---

## Task 5: Post-deploy verification (after Flux reconciles)

**Files:** none

- [ ] **Step 1: Flux and workload readiness**

Run:
```bash
kubectl -n flux-system get kustomization homepage
kubectl -n default get externalsecret homepage-env
kubectl -n default get secret homepage-env
kubectl -n default get pods -l app.kubernetes.io/name=homepage
```
Expected: Kustomization `Ready=True`; ExternalSecret `SecretSynced=True`;
Secret `homepage-env` exists; pod `Running` and `Ready`.

- [ ] **Step 2: Rollout sanity — no startup validation errors**

Run:
```bash
kubectl -n default logs deploy/homepage --tail=100 | rg -i "auth|oidc|error" || true
```
Expected: no fatal startup errors. A thrown error about `HOMEPAGE_EXTERNAL_URL`,
a missing secret, or a partial OIDC config means the env wiring is wrong.

- [ ] **Step 3: Healthcheck stays public**

Run:
```bash
curl -s -o /dev/null -w '%{http_code}\n' https://home.techtales.io/api/healthcheck
```
Expected: `200` (allowlisted; must work unauthenticated).

- [ ] **Step 4: Positive login test**

In a private/incognito window: open `https://home.techtales.io` → expect a
redirect to `/auth/signin` → sign in with a Pocket ID user in the `users` group →
expect the dashboard to render and widget tiles to load.

- [ ] **Step 5: Negative authorization test**

In a private window, sign in as a Pocket ID user **not** in the `users` group.
Expected: Pocket ID shows *"You are not allowed to access this service."* and
Homepage is not reached.

- [ ] **Step 6: Sign-out test**

Use the sign-out button in the dashboard header. Expected: session cleared and
returned to the sign-in page.

---

## Rollback

- **Fast:** set `HOMEPAGE_AUTH_ENABLED: "false"` in `helm-release.yaml`, commit,
  and let Flux reconcile (or remove the `envFrom` block). This disables the gate
  without reverting the external secret.
- **Full:** `git revert` the Task 1 and Task 2 commits and push to `main` via PR.
- No data migration is associated with this change.
