# Firecrawl → `firecrawl-system` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move firecrawl from the shared `ai` namespace into a new dedicated `firecrawl-system` namespace with its own Dragonfly cluster, driven by the existing `components/dragonfly` component.

**Architecture:** Create `kubernetes/main/apps/firecrawl-system/` (mirroring the `anubis-system` layout). Git-move `ai/firecrawl/` to `firecrawl-system/firecrawl/`. Update the `Kustomization` to target `firecrawl-system`, include the dragonfly component, and depend on `dragonfly-crds` (the operator CRD, not the shared cluster). Repoint `REDIS_URL`, `PLAYWRIGHT_MICROSERVICE_URL`, and `NUQ_DATABASE_URL` to the new namespace. Move the `ExternalSecret` to a new OpenBao path.

**Tech Stack:** Flux CD, kustomize components, Dragonfly Operator, bjw-s app-template v5.0.1, External Secrets Operator.

**Spec:** `docs/superpowers/specs/2026-06-25-firecrawl-system-dragonfly-design.md`

---

## File Structure

### New files

| File | Purpose |
|------|---------|
| `kubernetes/main/apps/firecrawl-system/namespace.yaml` | `Namespace` resource for `firecrawl-system` |
| `kubernetes/main/apps/firecrawl-system/kustomization.yaml` | Parent kustomization: namespace, flux alerts component, refs |

### Moved files (via `git mv`)

| From | To |
|------|-----|
| `kubernetes/main/apps/ai/firecrawl/flux-sync.yaml` | `kubernetes/main/apps/firecrawl-system/firecrawl/flux-sync.yaml` |
| `kubernetes/main/apps/ai/firecrawl/app/helm-release.yaml` | `kubernetes/main/apps/firecrawl-system/firecrawl/app/helm-release.yaml` |
| `kubernetes/main/apps/ai/firecrawl/app/external-secret.yaml` | `kubernetes/main/apps/firecrawl-system/firecrawl/app/external-secret.yaml` |
| `kubernetes/main/apps/ai/firecrawl/app/kustomization.yaml` | `kubernetes/main/apps/firecrawl-system/firecrawl/app/kustomization.yaml` |

### Modified files

| File | Change |
|------|--------|
| `kubernetes/main/apps/ai/kustomization.yaml` | Remove `- ./firecrawl/flux-sync.yaml` |

---

## Task 1: Create the `firecrawl-system` namespace and parent kustomization

**Files:**
- Create: `kubernetes/main/apps/firecrawl-system/namespace.yaml`
- Create: `kubernetes/main/apps/firecrawl-system/kustomization.yaml`

- [ ] **Step 1: Create `namespace.yaml`**

Create `kubernetes/main/apps/firecrawl-system/namespace.yaml` with:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master/namespace.json
apiVersion: v1
kind: Namespace
metadata:
  name: firecrawl-system
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 2: Create `kustomization.yaml`**

Create `kubernetes/main/apps/firecrawl-system/kustomization.yaml` with:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: firecrawl-system
components:
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./firecrawl/flux-sync.yaml
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/firecrawl-system/namespace.yaml \
        kubernetes/main/apps/firecrawl-system/kustomization.yaml
git commit -S -m "feat(firecrawl-system): scaffold namespace and parent kustomization"
```

---

## Task 2: Move `firecrawl` from `ai/` to `firecrawl-system/`

**Files:**
- Move: `kubernetes/main/apps/ai/firecrawl/` → `kubernetes/main/apps/firecrawl-system/firecrawl/`

- [ ] **Step 1: Git-move the directory**

```bash
git mv kubernetes/main/apps/ai/firecrawl kubernetes/main/apps/firecrawl-system/firecrawl
```

- [ ] **Step 2: Verify the move**

```bash
ls kubernetes/main/apps/ai/firecrawl 2>/dev/null && echo "ERROR: still in ai" || echo "ok"
ls kubernetes/main/apps/firecrawl-system/firecrawl
```

Expected: `ok` and listing of `app/` and `flux-sync.yaml`.

- [ ] **Step 3: Commit (no content changes yet)**

If `git mv` produced a single staged change, commit it as-is:

```bash
git status
git commit -S -m "refactor(firecrawl): move app directory from ai to firecrawl-system"
```

If `git mv` did not auto-stage, stage the moves explicitly:

```bash
git add -A kubernetes/main/apps/ai/firecrawl kubernetes/main/apps/firecrawl-system/firecrawl
git commit -S -m "refactor(firecrawl): move app directory from ai to firecrawl-system"
```

---

## Task 3: Update `flux-sync.yaml` for `firecrawl-system`

**File:** `kubernetes/main/apps/firecrawl-system/firecrawl/flux-sync.yaml`

- [ ] **Step 1: Replace the file contents**

Overwrite the file with:

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app firecrawl
  namespace: &namespace firecrawl-system
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/dragonfly
  path: ./kubernetes/main/apps/firecrawl-system/firecrawl/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: dragonfly-crds
      namespace: dragonfly-system
    - name: cnpg-cluster
      namespace: cnpg-system
    - name: external-secrets-stores
      namespace: secops
  postBuild:
    substitute:
      APP: *app
      NAMESPACE: *namespace
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/firecrawl-system/firecrawl/flux-sync.yaml
git commit -S -m "feat(firecrawl): add own dragonfly via component, target firecrawl-system"
```

---

## Task 4: Repoint `helm-release.yaml` URLs to `firecrawl-system`

**File:** `kubernetes/main/apps/firecrawl-system/firecrawl/app/helm-release.yaml`

- [ ] **Step 1: Replace `REDIS_URL` and `REDIS_RATE_LIMIT_URL` in all three controllers**

In each of the `api`, `worker`, and `nuq-worker` controller blocks, change:

```yaml
              REDIS_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://dragonfly.dragonfly-system.svc.cluster.local:6379
```

to:

```yaml
              REDIS_URL: redis://firecrawl-dragonfly.firecrawl-system.svc.cluster.local:6379
              REDIS_RATE_LIMIT_URL: redis://firecrawl-dragonfly.firecrawl-system.svc.cluster.local:6379
```

This affects 3 controllers × 2 lines = 6 lines total.

- [ ] **Step 2: Replace `PLAYWRIGHT_MICROSERVICE_URL` in all three controllers**

In each of the `api`, `worker`, and `nuq-worker` controller blocks, change:

```yaml
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.ai.svc.cluster.local:3000/scrape #NOSONAR allow http
```

to:

```yaml
              PLAYWRIGHT_MICROSERVICE_URL: http://firecrawl-playwright.firecrawl-system.svc.cluster.local:3000/scrape #NOSONAR allow http
```

This affects 3 controllers × 1 line = 3 lines total.

- [ ] **Step 3: Replace `NUQ_DATABASE_URL` in `api` and `nuq-worker` controllers**

In the `api` and `nuq-worker` controller blocks, change:

```yaml
              NUQ_DATABASE_URL: postgresql://postgres:password@firecrawl-nuq-postgres.ai.svc.cluster.local:5432/postgres
```

to:

```yaml
              NUQ_DATABASE_URL: postgresql://postgres:password@firecrawl-nuq-postgres.firecrawl-system.svc.cluster.local:5432/postgres
```

This affects 2 controllers × 1 line = 2 lines total.

- [ ] **Step 4: Sanity check no `ai.svc.cluster.local` references remain**

```bash
grep -n "ai.svc.cluster.local" kubernetes/main/apps/firecrawl-system/firecrawl/app/helm-release.yaml || echo "ok"
```

Expected: `ok`.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/firecrawl-system/firecrawl/app/helm-release.yaml
git commit -S -m "feat(firecrawl): repoint redis, playwright, nuq URLs to firecrawl-system"
```

---

## Task 5: Update `ExternalSecret` to the new OpenBao path

**File:** `kubernetes/main/apps/firecrawl-system/firecrawl/app/external-secret.yaml`

- [ ] **Step 1: Replace the `key` value**

Change:

```yaml
  dataFrom:
    - extract:
        key: infra/kubernetes/main/ai/firecrawl #gitleaks:allow
```

to:

```yaml
  dataFrom:
    - extract:
        key: infra/kubernetes/main/firecrawl-system/firecrawl #gitleaks:allow
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/firecrawl-system/firecrawl/app/external-secret.yaml
git commit -S -m "feat(firecrawl): move external secret path to firecrawl-system"
```

---

## Task 6: Remove firecrawl from the `ai` kustomization

**File:** `kubernetes/main/apps/ai/kustomization.yaml`

- [ ] **Step 1: Remove the firecrawl entry**

Edit `kubernetes/main/apps/ai/kustomization.yaml` and delete the line:

```yaml
  - ./firecrawl/flux-sync.yaml
```

The full file should become:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ai
components:
  - ../../../components/flux/alerts
resources:
  - ./namespace.yaml
  - ./llm-guard/flux-sync.yaml
  - ./olla/flux-sync.yaml
  - ./ollama/flux-sync.yaml
  - ./open-webui/flux-sync.yaml
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/ai/kustomization.yaml
git commit -S -m "refactor(ai): drop firecrawl from kustomization"
```

---

## Task 7: Validate with kustomize

**Files:** All new and modified files.

- [ ] **Step 1: Build the new `firecrawl-system` kustomization**

```bash
kustomize build kubernetes/main/apps/firecrawl-system/
```

Expected: Output contains
- `Namespace/firecrawl-system`
- `Kustomization/firecrawl-system/firecrawl` (with `components: [../../../../../components/dragonfly]`, `dependsOn` referencing `dragonfly-crds`)
- `Dragonfly/firecrawl-system/firecrawl-dragonfly`
- `PodMonitor/firecrawl-system/firecrawl-dragonfly`
- `NetworkPolicy/firecrawl-system/firecrawl-dragonfly-metrics`
- `RoleBinding/firecrawl-system/dragonfly-operator-write`
- `HelmRelease/firecrawl-system/firecrawl` with the updated `REDIS_URL`, `PLAYWRIGHT_MICROSERVICE_URL`, and `NUQ_DATABASE_URL`
- `ExternalSecret/firecrawl-system/firecrawl-env` with the updated OpenBao key

No errors. Exit code 0.

- [ ] **Step 2: Build the `ai` kustomization (should still work, minus firecrawl)**

```bash
kustomize build kubernetes/main/apps/ai/
```

Expected: Output contains `Kustomization/ai/{llm-guard,olla,ollama,open-webui}` and **does not** contain `Kustomization/ai/firecrawl`. No errors.

- [ ] **Step 3: Confirm `git status` is clean apart from expected files**

```bash
git status --porcelain
```

Expected: empty output.

If anything unexpected appears, fix and amend the appropriate commit.

---

## Manual Out-of-Band Step: Migrate the OpenBao secret

The OpenBao secret at `infra/kubernetes/main/ai/firecrawl` must be replicated to `infra/kubernetes/main/firecrawl-system/firecrawl` before Flux reconciles. The repo provides a helper task for this.

- [ ] **Step 1: Run the OpenBao copy task**

```bash
task openbao:copy -- SRC=infra/kubernetes/main/ai/firecrawl DST=infra/kubernetes/main/firecrawl-system/firecrawl
```

- [ ] **Step 2: Verify the destination tree exists in OpenBao**

```bash
bao kv list infra/kubernetes/main/firecrawl-system/
```

Expected: lists the secret key (e.g. `firecrawl`).

- [ ] **Step 3: After merge + reconcile, verify the `ExternalSecret` becomes Ready**

```bash
kubectl -n firecrawl-system get externalsecret firecrawl-env -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

Expected: `True` within 5 minutes of pushing.

## Rollout Verification

After merge and reconcile:

1. `kubectl -n firecrawl-system get pods` — firecrawl-api/worker/nuq-worker/playwright/nuq-postgres + firecrawl-dragonfly-0/1 all `Running`.
2. `kubectl -n firecrawl-system get dragonfly firecrawl-dragonfly` — `Ready: True`.
3. `kubectl -n firecrawl-system logs deploy/firecrawl-api | grep -i redis` — no connection errors; URL resolves to the new cluster.
4. `kubectl -n firecrawl-system get endpoints firecrawl-dragonfly` — 2 endpoints.
5. `kubectl -n ai get pods` — no firecrawl-related pods remain.
