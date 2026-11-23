# prek migration: replace MegaLinter and pre-commit

Issue: [#10151](https://github.com/tyriis/home-ops/issues/10151)
Status: revision 8, draft. Revision 8 keeps upstream hook repos and converts only the hooks that have no upstream repo.

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
   - `betterleaks`: local `language: system`, replaces gitleaks.
   - `editorconfig-checker`: local `language: system`, added for MegaLinter parity.
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

Local hooks and their tools:

| Hook                                                    | Tool                 | `.mise.toml` backend                             | Version |
| ------------------------------------------------------- | -------------------- | ------------------------------------------------ | ------- |
| betterleaks                                             | betterleaks          | `aqua:betterleaks/betterleaks`                   | 1.10.1  |
| editorconfig-checker                                    | editorconfig-checker | `aqua:editorconfig-checker/editorconfig-checker` | 4.0.2   |
| check-cnpg-barman-destinationpath, check-docker-compose | local scripts        | none                                             | none    |

Lint task tools (not hooks, used by `.taskfiles/lint`):

| Tool         | `.mise.toml` backend   | Version |
| ------------ | ---------------------- | ------- |
| markdownlint | `npm:markdownlint-cli` | 0.50.0  |
| prettier     | `npm:prettier`         | 3.10.1  |
| yamllint     | `pipx:yamllint`        | 1.38.0  |

Other tools:

- `prek` itself: `aqua:j178/prek`, 0.5.11.
- `pre-commit` (`aqua:pre-commit/pre-commit`, 4.7.0) stays pinned for transition, see
  Phase 1 step 1.

## Phase 1: local

1. Pin the tools in the hook map and lint task list in `.mise.toml`. Remove the
   gitleaks pin.
2. Keep every upstream hook repo in `.pre-commit-config.yaml` at its `rev`. Add a
   local `language: system` hook only for tools listed as local in the hook map.
3. Replace the gitleaks hook with a Betterleaks hook.
   Set `entry: betterleaks git --pre-commit --redact --staged` and
   `pass_filenames: false`.
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

| Linter               | MegaLinter tool version | prek pin | Result                                                                                                                                                                                                                           |
| -------------------- | ----------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| actionlint           | 1.7.12                  | 1.7.12   | Match. 0 errors.                                                                                                                                                                                                                 |
| editorconfig-checker | 4.0.2                   | 4.0.2    | Match. 0 errors after the ComfyUI README list indent fix.                                                                                                                                                                        |
| prettier (JSON)      | 3.9.10                  | 3.10.1   | Match. 0 errors.                                                                                                                                                                                                                 |
| markdownlint         | 0.49.1                  | 0.50.0   | Match. 0 errors. Version differs; MegaLinter bundles 0.49.1.                                                                                                                                                                     |
| betterleaks          | 1.7.3                   | 1.10.1   | Match. 0 findings. Version differs; MegaLinter bundles 1.7.3.                                                                                                                                                                    |
| prettier (YAML)      | 3.9.10                  | 3.10.1   | Difference. MegaLinter reports 1 error on `kubernetes/main/apps/gaming/minecraft-java/flux-sync.yaml`: prettier 3.9.10 wants one extra trailing blank line. Prettier 3.10.1 passes the file. The file is not changed in phase 1. |
| yamllint             | 1.38.0                  | 1.38.0   | Match. 0 errors.                                                                                                                                                                                                                 |

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
   Tested flags: `--report-format` and `--report-path` exist in betterleaks 1.10.1.
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
