# prek migration: replace MegaLinter and pre-commit

Issue: [#10151](https://github.com/tyriis/home-ops/issues/10151)
Status: revision 12, draft. Revision 12 removes the lint-task tool pins and the pre-commit pin.

## Context

- The MegaLinter job pulls a 1.41 GB Docker image on every run.
- The pull is the largest part of the job. Issue #10151 estimates about 65% of
  the 70 to 100 second job time. This is an estimate, not checked against run data.
- The current workflow does not cache the image. The pull runs before the
  MegaLinter action starts.

## Purpose

- One runner, prek, runs the lint hooks locally and in CI.
- Local hooks and CI use the same config: `.pre-commit-config.yaml`.
- Upstream hook repos stay remote and keep their `rev`, as on `main`.
- Tool versions for local hooks and lint tasks come from `.mise.toml` only.
- CI no longer pulls the MegaLinter Docker image.

## Decisions

| Topic                | Decision                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Config file          | `.pre-commit-config.yaml`. Stays YAML. Renovate's pre-commit manager reads it today.                                          |
| Hook language        | Upstream hook repos stay remote with their `rev`. Only hooks with no upstream repo use `language: system`.                    |
| Tool source          | `.mise.toml` pins the tools that local hooks and lint tasks call. Remote hooks install their own environment.                 |
| Local stages         | `pre-commit` and `pre-push`.                                                                                                  |
| CI trigger           | `pull_request`: `opened`, `reopened`, `synchronize`, `ready_for_review`, `edited`. Also `workflow_dispatch`. No push trigger. |
| CI scope             | Changed files on pull requests. Full tree on `workflow_dispatch`.                                                             |
| Secret scan, local   | Betterleaks, staged mode. Scans the staged diff only. `--all-files` does not change this.                                     |
| Secret scan, CI      | Betterleaks on the pull request commit range. Pull requests only.                                                             |
| Secret scan, nightly | Betterleaks full history, SARIF. Phase 3 only.                                                                                |
| CI output            | Log only. No inline annotations.                                                                                              |
| Excluded             | proselint, `flux-check-hook`, self-hosted runner, custom image.                                                               |

Parity baseline: MegaLinter has 7 active linters in this repo. SPELL_PROSELINT is
inactive: it needs `.proselintrc.json` or proselint/config.json, and neither exists.

## Decided exceptions

1. `check-docker-compose` stays in CI. It runs only on pull requests that change
   `docker/**/compose.yaml`. Phase 2 tests it on such a pull request.
2. Upstream hook repos stay remote. Each keeps its `repo`, `rev`, and fields from
   `main`. prek runs them as pre-commit does. Renovate's pre-commit manager tracks
   their `rev`. Hooks with no upstream repo are local hooks, as listed below:
   - `betterleaks`: upstream betterleaks repo at stable `v1.10.1`, hook `betterleaks`
     (`language: golang`). Replaces gitleaks.
   - `editorconfig-checker`: upstream editorconfig-checker repo at stable `v4.0.2`,
     hook `editorconfig-checker` (`language: golang`). Added for MegaLinter parity.
     Commented out in `.pre-commit-config.yaml` until the `docs/superpowers/` lint
     decision is made. The hook is not dropped.
     Only stable releases are used. Prerelease tags are not pinned.
   - `check-cnpg-barman-destinationpath`, `check-docker-compose`: local scripts, unchanged.
   - `check-illegal-windows-names`: upstream pre-commit-hooks, unchanged.

## How the tools run

Local:

1. `prek install --hook-command 'mise exec -- prek'` writes the git shims.
   The shim starts prek through mise, so pinned tools are on `PATH`.
2. A commit or push runs the shim.
3. prek runs each remote hook in its own environment. Each local `language: system`
   hook finds its tool on `PATH`.

Manual run: `mise install && mise exec -- prek run --all-files`.

Local tasks call tools through `mise exec --`. The repository tasks do not call mise
today, so they need the shell to have mise on `PATH`. Wrapping each lint
command removes that assumption. The task list in `.taskfiles/lint` and
`.taskfiles/pre-commit` changes in phase 1.

CI:

1. `jdx/mise-action` installs the tools in `.mise.toml`.
2. On pull requests, `mise exec -- prek run --from-ref <base.sha> --to-ref <head.sha>` runs the hooks.
3. On pull requests, a Betterleaks step scans the commit range (see Phase 2).

Fixing hooks in CI: apply fixes locally. In CI, run the same hooks as checks.
A check fails with a diff when a fix would change files. CI never commits fixes.

### Why not `language: mise`

prek supports `language: mise`. The hook installs the tool from its own
`additional_dependencies` list. Tested with prek 0.5.11 on 2026-11-18: the hook
passes with no mise on `PATH`, and it also passes under `mise exec`.

It is still not the choice:

- The pins live in the hook, not in `.mise.toml`. Each tool then has two pins.
- The hook needs prek. Upstream pre-commit does not run it.
- The `additional_dependencies` list is only in the hook config.
  The config file format does not change this. prek reads YAML and TOML.
  So `prek.toml` is not required for this feature.

Decision: `language: system`, with pins in `.mise.toml` only.

## Hook map

Upstream repos are not converted. The `rev` of each remote hook stays as on `main`.
Remote hooks keep their `repo`, `rev`, `hooks`, and `args`.

Hooks that have no upstream repo are local. Currently: the two local scripts only.
The betterleaks and editorconfig-checker hooks are remote. The editorconfig-checker
hook is commented out for now.

The lint tasks (`.taskfiles/lint`) run their checks through prek hooks
(`markdownlint-fix`, `yamllint`, `prettier`). The hooks install their own tools, so
`.mise.toml` has no pins for them.

Other tools:

- `prek` itself: `aqua:j178/prek`, 0.5.11.
- `pre-commit` is not pinned. No repo file calls it. The Taskfile and the git shims use prek.

## Phase 1: local

1. Pin the local tools in `.mise.toml`. Remove the gitleaks pin. The lint tasks need
   no pins, because they run the hooks.
2. Keep every upstream hook repo in `.pre-commit-config.yaml` at its `rev`. Add a
   local hook only for tools with no upstream repo.
3. Replace the gitleaks hook with the upstream betterleaks repo at
   `v1.10.1`, hook `betterleaks`. The upstream hook builds its own binary.
   Remove the betterleaks pin from `.mise.toml`.
4. Add `default_install_hook_types: [pre-commit, pre-push]`.
5. Update the task files:
   - `.taskfiles/pre-commit/Taskfile.yaml`: `mise install` and `mise exec -- prek run --all-files`.
   - The `init` task: `prek install --hook-command 'mise exec -- prek'`.
   - `.taskfiles/devenv/check.yaml:25` and `.taskfiles/devenv/Taskfile.yaml:76-77`.
6. Update references: `AGENTS.md` line 125, `README.md` (lines 16, 207, 228-229),
   and `docs/backstage/systems/main-cluster/docs/index.md:72`.
7. `.github/labels.yaml`: rename or update the `renovate/pre-commit` label to
   match the new Renovate manager. Lines 93-94 and 157.
8. Confirm that Renovate updates a new `.mise.toml` pin. Do this before phase 1 closes.

Exit check:

- `prek validate-config .pre-commit-config.yaml` exits 0.
- Run MegaLinter with `VALIDATE_ALL_CODEBASE: true` on the branch.
- Run `mise exec -- prek run --all-files` on the same commit.
- Each of the 7 active MegaLinter linters must match its prek hook. Each difference
  must be written down with a reason.

Exit check results (MegaLinter 10.2.0, flavor terraform, run 2026-11-23):

| Linter               | MegaLinter tool version | prek pin                  | Result                                                       |
| -------------------- | ----------------------- | ------------------------- | ------------------------------------------------------------ |
| actionlint           | 1.7.12                  | 1.7.12                    | Match. 0 errors.                                             |
| editorconfig-checker | 4.0.2                   | 4.0.2 (Go, upstream repo) | Pending. Hook commented out. See note 1.                     |
| prettier (JSON)      | 3.9.10                  | 3.10.1                    | Match. 0 errors.                                             |
| markdownlint         | 0.49.1                  | 0.50.0                    | Match. 0 errors. Version differs; MegaLinter bundles 0.49.1. |
| betterleaks          | 1.7.3                   | v1.10.1                   | Match. 0 findings. See note 2.                               |
| prettier (YAML)      | 3.9.10                  | 3.10.1                    | Difference. See note 3.                                      |
| yamllint             | 1.38.0                  | 1.38.0                    | Match. 0 errors.                                             |

Notes:

1. editorconfig-checker: the Go hook at v4.0.2 reports findings only under `docs/superpowers/`. The hook is commented out until the docs lint decision is made. Re-check parity before phase 1 closes.
2. betterleaks: the upstream hook builds stable v1.10.1. MegaLinter bundles 1.7.3.
3. prettier (YAML): MegaLinter reports 1 error on `kubernetes/main/apps/gaming/minecraft-java/flux-sync.yaml`. Prettier 3.9.10 wants one extra trailing blank line. Prettier 3.10.1 passes the file. The file is not changed in phase 1.

`prek run --all-files` passes every hook on the same tree. `check-illegal-windows-names`
and `check-xml` have no files to check. The `betterleaks` hook (staged) reports no
findings. A full-tree secret scan is not part of phase 1 (see Secret scan scope).

## Phase 2: CI

1. Add `.github/workflows/lint.yaml`:
   - Triggers: the five pull request types (`opened`, `reopened`, `synchronize`,
     `ready_for_review`, `edited`), and `workflow_dispatch`.
   - Workflow-level `permissions: contents: read`.
   - Workflow-level `env: PREK_SKIP: no-commit-to-branch`. The hook does not apply
     to pull requests or to `workflow_dispatch` runs on `main`.
   - `actions/checkout` with `fetch-depth: 0`.
   - `jdx/mise-action` (SHA pinned) installs `.mise.toml` tools.
   - On pull requests: `mise exec -- prek run --from-ref <base.sha> --to-ref <head.sha> --show-diff-on-failure`.
   - On `workflow_dispatch`: `mise exec -- prek run --all-files --show-diff-on-failure`.
   - On pull requests only: `betterleaks git . --log-opts="<base.sha>..<head.sha>" --redact`.
     CI needs a betterleaks binary. Pin it in `.mise.toml` at the same stable version (1.10.1) in phase 2.
     Tested with betterleaks 1.10.1 on a sample repository: the range finds a
     committed token, and an empty range finds none.
   - `workflow_dispatch` has no pull request range. It runs no separate secret scan.
     The full-history scan is phase 3.
   - `check-docker-compose` runs as a normal hook. It stays in CI.
   - `harden-runner` with `egress-policy: audit`. Keep audit on purpose.
   - `concurrency` to cancel superseded runs.
   - SHA-pin every action.
2. Apply the `github-actions-hardening` and `github-actions-efficiency` skills to the file.
3. Delete `.github/workflows/mega-linter.yaml` and `.mega-linter.yaml` before the exit check.

Exit check: a test pull request is green. A test pull request that changes a
`docker/**/compose.yaml` file runs `check-docker-compose`. A deliberate lint error makes it red.
A deliberate committed token makes the Betterleaks step red. MegaLinter does not run.

Rollback: one revert that restores the two MegaLinter files and removes `lint.yaml`.

## Phase 3: nightly

1. Add a scheduled workflow that runs a full-history Betterleaks scan with SARIF output:
   `betterleaks git . --report-format sarif --report-path <file> --redact`.
   Flags tested on 1.10.1, the stable release used by the hook.
2. Grant `security-events: write`. Upload with `github/codeql-action/upload-sarif`, SHA pinned.
3. Allow findings without failing the job. Triage the historical findings first.

Exit check: the scheduled run completes and SARIF appears in code scanning.

## Secret scan scope

- Staged mode scans only the staged diff. Unstaged and untracked files are not scanned.
- `prek run --all-files` runs the staged hook. With `pass_filenames: false`, the
  hook still reads only the index. Result: a full run does not scan the tree.
- This is not new. The current gitleaks hook runs `gitleaks git --pre-commit --staged`.
  Tested 2026-11-18 with a committed token: gitleaks scanned about 0 bytes and passed.
  Betterleaks behaves the same.
- Until phase 3, the repository has no full-tree secret scan in the local hooks.
  The phase 2 commit-range step covers only pull request commits. Interim gap: a
  secret committed to main outside a pull request is not scanned by prek.

## Risks

- The PR gate checks changed files. Full-tree checks run on `workflow_dispatch`.
- Staged Betterleaks does not see untracked files. Phase 3 covers full history.
- The first nightly run may show old secrets. Triage them before phase 3 closes.

## Addendum: changes after revision 11

This addendum records what changed in the implementation after the spec was written,
and why. It does not replace the sections above.

### Hook sources

- Upstream hook repos stay remote. The first implementation converted them to
  `language: system`. That conversion was reverted. Reason: upstream repos already
  pin each tool with a `rev`. Renovate tracks those revs. A local copy duplicates each
  pin and needs mise on `PATH`.
- betterleaks: the upstream repo `betterleaks/betterleaks` at stable `v1.10.1`, hook
  `betterleaks` (`language: golang`). Reason: the prerelease `v2.0.0-rc.10` was
  rejected, because only stable releases are pinned. Stable `v1.10.1` is the release
  the earlier tests used. The hook builds its own binary, so `.mise.toml` has no
  betterleaks pin.
- editorconfig-checker: the upstream repo `editorconfig-checker/editorconfig-checker`
  at stable `v4.0.2`, hook `editorconfig-checker` (`language: golang`). It is
  commented out in `.pre-commit-config.yaml` with a `TODO` anchor. Reason: on the merged
  tree it reports findings only under `docs/superpowers/`. Main removed the exclude for
  those docs in `62c257d1c`. The hook is not dropped. It returns when the owner
  decides how to handle those docs.
- editorconfig-checker python repo (3.11.1): rejected. It is a different tool from the
  Go binary that the MegaLinter comparison used.

### Tool pins

- `.mise.toml` no longer pins markdownlint-cli, prettier, yamllint, betterleaks,
  editorconfig-checker or pre-commit. Reason: the hooks install their own tools. The
  lint tasks call the hooks, so no tool needs a repo pin.
- The `prek` pin (`aqua:j178/prek` 0.5.11) stays. It runs the hooks.

### Lint tasks

- `.taskfiles/lint/Taskfile.yaml` runs `prek run <hook> --all-files` for
  `markdownlint-fix`, `yamllint` and `prettier`. Reason: no tool needs `mise exec`
  or a pin. Two effects follow. The prettier hook writes files, so the prettier check
  also rewrites files. The markdownlint hook fixes what it finds.

- Repo tasks do not call `mise exec --` and do not run `mise install`. Reason: the
  task files should call the tool directly. `.taskfiles/pre-commit` runs `prek install`
  and `prek run --all-files`. The `mise install` step and the `mise exec` wrapper in
  phase 1 step 5 are superseded.

### Annotations

- `gitleaks:allow` is renamed to `betterleaks:allow` in 17 files. Reason: gitleaks is
  no longer in the hook set. betterleaks 1.10.1 accepts both forms. A test showed that
  each form suppresses a finding on a staged file.
- Two findings in `docs/superpowers/plans/2026-06-25-firecrawl-system-dragonfly.md` are
  placeholders (`postgres:password`). They carry `# betterleaks:allow`. Reason: the
  hook scans staged content, and the placeholder is not a secret.

### Merge with main

- `main` was merged into the branch in `6b4eaad5c`. Pin conflicts in `.mise.toml`
  resolved to main's newer versions for vcluster, flux2, flux-operator-mcp and openbao.
  The gitleaks pin stayed removed.
- Main added the `docs/superpowers/` linting policy in `62c257d1c`. The editorconfig
  hook conflicts with that policy. Open decision: exclude those docs from this hook,
  fix the docs, or drop the hook.

### Measurements

- On this repository, both tools ran the same 33 hooks and passed.
  `prek run --all-files` took 11.2 s and 11.8 s. `pre-commit run --all-files` took
  15.5 s and 15.7 s. The runs were on one machine. Reason: the migration goal includes
  faster local and CI runs.

### Open items

- The editorconfig-checker hook stays commented out until the `docs/superpowers/`
  decision is made.
- Phase 2 must pin betterleaks 1.10.1 in `.mise.toml`, because the CI step calls the
  CLI directly.
- Phase 3 must re-test the betterleaks commands on the same stable release.
