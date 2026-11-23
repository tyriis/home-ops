# prek migration: replace MegaLinter and pre-commit

Issue: [#10151](https://github.com/tyriis/home-ops/issues/10151)
Status: revision 7, draft. Not committed. Last commit on the PR: revision 6.

## Context

- The MegaLinter job pulls a 1.41 GB Docker image on every run.
- The pull is the largest part of the job. Issue #10151 estimates about 65% of
  the 70 to 100 second job time. This is an estimate, not checked against run data.
- The current workflow does not cache the image. The pull runs before the
  MegaLinter action starts.

## Purpose

- One runner, prek, runs the lint hooks locally and in CI.
- Local hooks and CI use the same config: `.pre-commit-config.yaml`.
- Tool versions come from `.mise.toml` only.
- CI no longer pulls the MegaLinter Docker image.

## Decisions

| Topic                | Decision                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Config file          | `.pre-commit-config.yaml`. Stays YAML. Renovate's pre-commit manager reads it today.                                          |
| Hook language        | `system` for every hook except the three remote hooks in Decided exceptions.                                                  |
| Tool source          | `.mise.toml`. mise installs the tools, except the three remote hooks.                                                         |
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
2. Three remote hooks stay remote. They have no backend in `.mise.toml`:
   - `remove-crlf`, `remove-tabs`: Lucas-C/pre-commit-hooks v1.5.6.
   - `forbid-secrets`: k8s-at-home/sops-pre-commit v2.1.1.

   Each keeps its `repo`, `rev`, and `language: python` from upstream. prek builds
   the hook environment. Renovate's pre-commit manager tracks the `rev`. Behavior
   does not change. These are the only hooks outside `.mise.toml`.

## How the tools run

Local:

1. `prek install --hook-command 'mise exec -- prek'` writes the git shims.
   The shim starts prek through mise, so pinned tools are on `PATH`.
2. A commit or push runs the shim.
3. prek runs each hook with `language: system`. The hook command finds its tool on `PATH`.

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

Every hook in `.pre-commit-config.yaml` on `main` appears once below. Each remote
hook becomes a local `language: system` hook. Tool versions move to `.mise.toml`.

Backends and versions were checked with `mise ls-remote` on 2026-11-18.

### Fixing hooks (rewrite files)

| Hook                                                                                              | Tool             | `.mise.toml` backend    | Version |
| ------------------------------------------------------------------------------------------------- | ---------------- | ----------------------- | ------- |
| doctoc                                                                                            | doctoc           | `npm:doctoc`            | 2.5.0   |
| markdownlint-fix                                                                                  | markdownlint     | `npm:markdownlint-cli`  | 0.50.0  |
| prettier                                                                                          | prettier         | `npm:prettier`          | 3.10.1  |
| end-of-file-fixer, trailing-whitespace, mixed-line-ending, fix-byte-order-marker                  | pre-commit-hooks | `pipx:pre-commit-hooks` | 6.0.0   |
| remove-crlf, remove-tabs                                                                          | Lucas-C (remote) | Remote hook, see Decided exceptions | 1.5.6 |
| fix-smartquotes, fix-ligatures                                                                    | texthooks        | `pipx:texthooks`        | 1.0.0   |

### Checking hooks (report only)

| Hook                                                                                                                                                             | Tool                                  | `.mise.toml` backend                             | Version         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------ | --------------- |
| check-useless-excludes                                                                                                                                           | prek built-in (`meta`)                | none                                             | none            |
| check-cnpg-barman-destinationpath                                                                                                                                | local script                          | none                                             | none            |
| check-docker-compose                                                                                                                                             | local script, needs docker compose and PyYAML | none                                     | none            |
| check-added-large-files, check-case-conflict, check-executables-have-shebangs, check-merge-conflict, check-shebang-scripts-are-executable, check-symlinks, check-vcs-permalinks, destroyed-symlinks, detect-aws-credentials, detect-private-key, no-commit-to-branch, check-json, check-toml, check-xml, check-yaml | pre-commit-hooks | `pipx:pre-commit-hooks` | 6.0.0           |
| check-illegal-windows-names                                                                                                                                      | pre-commit-hooks, local `language: fail` copy | none (no binary needed) | none     |
| yamllint                                                                                                                                                         | yamllint                              | `pipx:yamllint`                                  | 1.38.0          |
| forbid-bidi-controls                                                                                                                                             | texthooks                             | `pipx:texthooks`                                 | 1.0.0           |
| forbid-secrets                                                                                                                                                   | sops-pre-commit (remote hook)                 | Remote hook, see Decided exceptions      | v2.1.1          |
| gitleaks (replaced by betterleaks)                                                                                                                               | betterleaks                           | `aqua:betterleaks/betterleaks`                   | 1.10.1          |
| actionlint                                                                                                                                                       | actionlint                            | `aqua:rhysd/actionlint`                          | 1.7.12          |
| editorconfig-checker (no hook in the config today; added for MegaLinter parity)                                                                                  | editorconfig-checker                  | `aqua:editorconfig-checker/editorconfig-checker` | 4.0.2           |

Other tools:

- `prek` itself: `aqua:j178/prek`, 0.5.11.
- The editorconfig-checker v4.0.2 binary is `editorconfig-checker`, checked with `mise exec`.

Rules for each mapped hook (phase 1, step 2):

- Copy every manifest field that changes behavior: `types`, `types_or`, `exclude_types`, `stages`, `always_run`, `pass_filenames`, `require_serial`, and `args`.
- For example, prettier needs `types: [text]`. `no-commit-to-branch` needs `always_run: true`.
- Record the upstream `entry` for each hook in the change.

mirrors-prettier also formats Markdown, JSON, and YAML. The local prettier hook
must cover the same file types as the parity baseline (JSON and YAML). Markdown
is also covered by markdownlint.

## Phase 1: local

1. Add the tools in the hook map to `.mise.toml`.
2. Convert each remote hook in `.pre-commit-config.yaml` to a local
   `language: system` hook. Apply the rules in the hook map section.
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

| Linter               | MegaLinter tool version | prek pin | Result                                                                                 |
| -------------------- | ----------------------- | -------- | -------------------------------------------------------------------------------------- |
| actionlint           | 1.7.12                  | 1.7.12   | Match. 0 errors.                                                                       |
| editorconfig-checker | 4.0.2                   | 4.0.2    | Match. 0 errors after the ComfyUI README list indent fix.                              |
| prettier (JSON)      | 3.9.10                  | 3.10.1   | Match. 0 errors.                                                                       |
| markdownlint         | 0.49.1                  | 0.50.0   | Match. 0 errors. Version differs; MegaLinter bundles 0.49.1.                           |
| betterleaks          | 1.7.3                   | 1.10.1   | Match. 0 findings. Version differs; MegaLinter bundles 1.7.3.                          |
| prettier (YAML)      | 3.9.10                  | 3.10.1   | Difference. MegaLinter reports 1 error on `kubernetes/main/apps/gaming/minecraft-java/flux-sync.yaml`: prettier 3.9.10 wants one extra trailing blank line. Prettier 3.10.1 passes the file. The file is not changed in phase 1. |
| yamllint             | 1.38.0                  | 1.38.0   | Match. 0 errors.                                                                       |

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

- Remote `rev` pins leave `.pre-commit-config.yaml`. The Renovate pre-commit
  manager reads only `.pre-commit-config.yaml`, so no Renovate manager tracks the
  remote pins after the change. Phase 1, step 8 must pass before phase 1 closes.
- The PR gate checks changed files. Full-tree checks run on `workflow_dispatch`.
- Staged Betterleaks does not see untracked files. Phase 3 covers full history.
- The first nightly run may show old secrets. Triage them before phase 3 closes.
