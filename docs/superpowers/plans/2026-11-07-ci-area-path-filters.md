# CI area path filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each CI gate start only when the files it validates change, so unrelated PRs stop burning runner minutes.

**Architecture:** Six edits to trigger blocks in `.github/workflows/*.yaml`. No new workflows, actions, or shared filters. Each gate keeps its current validation scope; only its `on:` block changes, plus a `concurrency` block on two workflows that lack one.

**Tech Stack:** GitHub Actions workflow YAML, Task (`task lint:*`), pre-commit (actionlint, yamllint, prettier).

**Spec:** `docs/superpowers/specs/2026-11-07-ci-area-path-filters-design.md`

## Global Constraints

- Branch: `feature/ci-area-path-filters` (branch naming rule: `<bugfix|feature>/<kebab-case>`, max 40 chars).
- Commit messages: conventional, imperative, ≤ 72 chars. Never squash.
- Run tooling through `task`, never ad-hoc scripts.
- The implementer is authorized and expected to fix formatting (prettier/yamllint) and add lint suppressions the repo's CI requires.
- No workflow deploys to a cluster; a wrong filter costs a validation gate, not a bad deploy.
- No gate is a required status check today, so a skipped workflow cannot block a merge.

## Review Focus

- A PR that edits a gate's own workflow file must start that gate — every task adds the workflow file to its own `paths`.
- A PR touching both `kubernetes/` and `docker/` must start both gates — `paths` are per-workflow, never exclusive.
- `kubernetes/` holds 4 `.yml` and 56 non-YAML files (60 non-`.yaml` in total) that the old `kubernetes/**.yaml` glob missed — Task 1 Step 4 asserts they now match.
- A `workflow_dispatch` run must still work after the trigger edit on `deadvalues` and `MegaLinter`.
- Renovate runs hourly; the new concurrency group must queue, not cancel, so two runs never overlap and neither is killed mid-update.

---

### Task 1: Scope the kubernetes gates

**Files:**
- Modify: `.github/workflows/deadvalues.yaml:12-16`
- Modify: `.github/workflows/flate.yaml:4-9`

**Interfaces:**
- Consumes: nothing.
- Produces: the `kubernetes/**` glob both later verification steps assert against.

- [ ] **Step 1: Write the failing check**

Run:
```bash
git ls-files 'kubernetes/**' | wc -l; git ls-files 'kubernetes/**.yaml' | wc -l
```
Expected: the second number is smaller than the first (the old glob misses `.yml` and non-YAML assets). Record both.

- [ ] **Step 2: Replace `deadvalues.yaml`'s trigger block**

```yaml
on:
  pull_request:
    branches:
      - main
    paths:
      - kubernetes/**
      - .deadvalues.yaml
      - .github/workflows/deadvalues.yaml
  workflow_dispatch:
```

`branches: [main]` is new: the workflow had no branch filter and ran on PRs to any branch. Keep `workflow_dispatch` untouched.

- [ ] **Step 3: Replace `flate.yaml`'s `paths`**

```yaml
    paths:
      - kubernetes/**
      - .github/workflows/flate.yaml
```

Leave `branches: [main]` as is.

- [ ] **Step 4: Verify the globs match what they should**

Run:
```bash
git ls-files 'kubernetes/**' | wc -l
git ls-files 'kubernetes/**' | grep -vc '^kubernetes/'
git ls-files 'kubernetes/**/*.yml' | wc -l
```
Expected: first count equals the first count from Step 1; the `grep -vc` prints `0`; the `.yml` count prints `4`.

- [ ] **Step 5: Confirm manual dispatch still works**

Run: `grep -c 'workflow_dispatch:' .github/workflows/deadvalues.yaml`
Expected: `1`.

- [ ] **Step 6: Lint**

Run: `task lint:yaml && pre-commit run actionlint --all-files`
Expected: both pass, no reformatting of the edited blocks.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/deadvalues.yaml .github/workflows/flate.yaml
git commit -m "ci: scope kubernetes gates to kubernetes changes"
```
---

### Task 2: Make the docker gate start on its own changes

**Files:**
- Modify: `.github/workflows/docker.yaml:8-10`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks rely on.

- [ ] **Step 1: Add the workflow file to `paths`**

```yaml
    paths:
      - docker/**
      - scripts/hooks/check-docker-compose.sh
      - .github/workflows/docker.yaml
```

- [ ] **Step 2: Verify the gate still matches every compose file**

Run: `git ls-files 'docker/**compose.y*ml' | wc -l`
Expected: a non-zero count; every path printed starts with `docker/`.

- [ ] **Step 3: Lint and commit**

```bash
task lint:yaml && pre-commit run actionlint --all-files
git add .github/workflows/docker.yaml
git commit -m "ci(docker): trigger on changes to the workflow itself"
```

---

### Task 3: Add concurrency to MegaLinter

**Files:**
- Modify: `.github/workflows/mega-linter.yaml:10-12`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks rely on.

- [ ] **Step 1: Insert the concurrency block after `on:`**

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.number || github.ref }}
  cancel-in-progress: true
```

Triggers stay unchanged on purpose: MegaLinter lints Markdown, YAML and JSON, so nearly every PR touches a file it would lint and a `paths` filter would be near-vacuous. The saving is cancelling superseded runs on rapid pushes.

- [ ] **Step 2: Lint and commit**

```bash
task lint:yaml && pre-commit run actionlint --all-files
git add .github/workflows/mega-linter.yaml
git commit -m "ci(mega-linter): cancel superseded runs"
```

---

### Task 4: Stop the runs that cannot produce a new result

**Files:**
- Modify: `.github/workflows/scorecards.yaml:17-19`
- Modify: `.github/workflows/schedule-renovate.yaml:18-25`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks rely on.

- [ ] **Step 1: Remove Scorecard's `push` trigger**

Delete the block:
```yaml
  push:
    branches:
      - main
```

Keep `branch_protection_rule` and the weekly `schedule`. The supply-chain report then refreshes weekly and on branch-protection changes instead of on every merge.

- [ ] **Step 2: Fix Renovate's push filter and add serial concurrency**

Remove the dead entry `.github/renovate/**.json5` (the directory does not exist). The `push.paths` list becomes:
```yaml
    paths:
      - .github/renovate.json5
      - .github/renovate-bot.json5
      - .github/workflows/schedule-renovate.yaml
```

Then add, above `env:`:
```yaml
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false
```

`cancel-in-progress: false` is deliberate: an hourly run must queue behind a running one rather than being killed mid-update.

- [ ] **Step 3: Verify no dead paths remain in any push filter**

Run:
```bash
grep -rn "renovate/\*\*" .github/workflows/ || echo "no dead renovate path"
for p in $(grep -A4 'paths:' .github/workflows/schedule-renovate.yaml | grep '^\s*-' | sed 's/^ *- //'); do test -e "$p" || echo "MISSING: $p"; done
```
Expected: `no dead renovate path`, then no `MISSING:` lines.

- [ ] **Step 4: Confirm the concurrency blocks are in place**

Run:
```bash
grep -A2 '^concurrency:' .github/workflows/schedule-renovate.yaml .github/workflows/mega-linter.yaml
```
Expected: two blocks; Renovate shows `cancel-in-progress: false`, MegaLinter `true`.

- [ ] **Step 5: Lint and commit**

```bash
task lint:yaml && pre-commit run actionlint --all-files
git add .github/workflows/scorecards.yaml .github/workflows/schedule-renovate.yaml
git commit -m "ci: stop scorecard and renovate runs that add nothing"
```

---

### Task 5: Whole-change verification

**Files:** none modified.

- [ ] **Step 1: Confirm every gate that has a `paths` filter lists itself**

Run:
```bash
for f in .github/workflows/*.yaml; do
  grep -q '^    paths:' "$f" && { grep -q "$(basename "$f")" "$f" && echo "ok   $f" || echo "SELF-MISSING $f"; }
done
```
Expected: `ok` for `deadvalues.yaml`, `docker.yaml`, `flate.yaml`, `schedule-renovate.yaml`, and no `SELF-MISSING`.

- [ ] **Step 1b: Confirm the gates stay independent**

Run: `grep -l '^    paths:' .github/workflows/*.yaml`
Expected: the four files above. Filters are per-workflow, so a PR touching both `kubernetes/` and `docker/` starts both — no task makes one workflow's paths exclusive of another's.

- [ ] **Step 2: Run the repository lint suite**

Run: `task lint:all && pre-commit run --all-files`
Expected: pass. Prettier must not rewrite the edited YAML; if it does, accept its formatting and amend the last commit.

- [ ] **Step 3: Review the diff**

Run: `git diff main --stat && git diff main -- .github/workflows`
Expected: 6 workflow files plus the spec, and every hunk inside an `on:`, `paths:`, `concurrency:` or a deleted trigger block — no change to steps, jobs or permissions.

- [ ] **Step 4: Push and ask before opening a PR**

```bash
git push -u origin feature/ci-area-path-filters
```
Then present the commits and ask whether to open a PR. Do not open one unasked.

Post-merge empirical check (owner, not implementer): a docs-only PR starts only MegaLinter, Dependency Review and the labeler; a `kubernetes/` PR starts `flate` and `deadvalues`; a `docker/` PR starts `docker` among the area gates — MegaLinter, Dependency Review and the labeler always run too.
