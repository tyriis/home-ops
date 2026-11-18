# prek migration: replace MegaLinter and pre-commit

Issue: [#10151](https://github.com/tyriis/home-ops/issues/10151)
Status: revision 3, draft. Not committed.

## Context

- The MegaLinter job pulls a 1.41 GB Docker image on every run.
- Measured in issue #10151: the job takes 70 to 100 seconds. About 65% of that is the pull.
- Hosted runners cannot cache the image. The pull runs before any step.

## Purpose

- One runner, prek, runs the lint hooks locally and in CI.
- Local hooks and CI use the same config: `.pre-commit-config.yaml`.
- Tool versions come from `.mise.toml` only.
- CI no longer pulls the MegaLinter Docker image.

## Decisions

| Topic                | Decision                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Config file          | `.pre-commit-config.yaml`. Stays YAML. Renovate reads it today.                                                     |
| Hook language        | `system` for every hook. prek runs the command on `PATH`.                                                           |
| Tool source          | `.mise.toml`. mise installs the tools.                                                                              |
| Local stages         | `pre-commit` and `pre-push`.                                                                                        |
| CI trigger           | `pull_request`: `opened`, `reopened`, `synchronize`, `ready_for_review`. Also `workflow_dispatch`. No push trigger. |
| CI scope             | Changed files on pull requests. Full tree on `workflow_dispatch`.                                                   |
| Secret scan, local   | Betterleaks, staged mode. Scans the staged diff only. `--all-files` does not change this.                                                                                           |
| Secret scan, CI      | Betterleaks on the pull request commit range.                                                                       |
| Secret scan, nightly | Betterleaks full history, SARIF. Phase 3 only.                                                                      |
| CI output            | Log only. No inline annotations.                                                                                    |
| Excluded             | proselint, `flux-check-hook`, self-hosted runner, custom image.                                                     |

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
2. `mise exec -- prek run --from-ref <base.sha> --to-ref <head.sha>` runs the hooks.
3. A commit-range Betterleaks step scans the pull request commits.

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

Each remote hook becomes a local `language: system` hook. The command and
arguments come from the upstream manifest. Tool versions move to `.mise.toml`.

| Hook                              | Tool                                          | `.mise.toml` backend                             | Version   |
| --------------------------------- | --------------------------------------------- | ------------------------------------------------ | --------- |
| prek                              | prek                                          | `aqua:j178/prek`                                 | 0.5.11    |
| betterleaks (replaces gitleaks)   | betterleaks                                   | `aqua:betterleaks/betterleaks`                   | 1.10.1    |
| actionlint                        | actionlint                                    | `aqua:rhysd/actionlint`                          | 1.7.12    |
| editorconfig-checker              | editorconfig-checker                          | `aqua:editorconfig-checker/editorconfig-checker` | 4.0.2     |
| prettier                          | prettier                                      | `npm:prettier`                                   | 3.10.1    |
| markdownlint                      | markdownlint                                  | `npm:markdownlint-cli`                           | 0.50.0    |
| doctoc                            | doctoc                                        | `npm:doctoc`                                     | 2.5.0     |
| yamllint                          | yamllint                                      | `pipx:yamllint`                                  | 1.38.0    |
| pre-commit-hooks                  | many (see open items)                         | `pipx:pre-commit-hooks`                          | 6.0.0     |
| texthooks                         | many (see open items)                         | `pipx:texthooks`                                 | 1.0.0     |
| remove-crlf, remove-tabs          | Lucas-C scripts                               | to verify                                        | to verify |
| forbid-secrets                    | sops-pre-commit script                        | to verify                                        | to verify |
| check-useless-excludes            | prek built-in (`meta`)                        | none                                             | none      |
| check-cnpg-barman-destinationpath | local script                                  | none                                             | none      |
| check-docker-compose              | local script, needs docker compose and PyYAML | none                                             | none      |

All backends and versions were checked with `mise ls-remote` on 2026-11-18.
The editorconfig-checker v4.0.2 binary is `editorconfig-checker`, checked with
`mise exec`.

## Phase 1: local

1. Add the tools in the hook map to `.mise.toml`.
2. Convert each remote hook in `.pre-commit-config.yaml` to a local
   `language: system` hook. Keep the arguments, `files`, and `exclude` values.
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
7. Restore the comments that the conversion drops by hand, if any remain.

Exit check: run MegaLinter with `VALIDATE_ALL_CODEBASE: true` on the branch.
Run `mise exec -- prek run --all-files` on the same commit. Every linter must match,
or each difference must be written down with a reason.

## Phase 2: CI

1. Add `.github/workflows/lint.yaml`:
   - Triggers: the four pull request types, and `workflow_dispatch`.
   - `actions/checkout` with `fetch-depth: 0`.
   - `jdx/mise-action` (SHA pinned) installs `.mise.toml` tools.
   - Pull requests run `mise exec -- prek run --from-ref <base.sha> --to-ref <head.sha> --show-diff-on-failure`.
   - `workflow_dispatch` runs `mise exec -- prek run --all-files` with `PREK_SKIP=no-commit-to-branch`.
   - A Betterleaks step scans `<base.sha>..<head.sha>` with `--redact`.
   - `check-docker-compose` needs PyYAML and docker compose on the runner. Verify before merge.
   - `harden-runner` with `egress-policy: audit`. Keep audit on purpose.
   - `concurrency` and `permissions: contents: read`.
   - SHA-pin every action.
2. Apply the `github-actions-hardening` and `github-actions-efficiency` skills to the file.
3. Delete `.github/workflows/mega-linter.yaml` and `.mega-linter.yaml` before the exit check.

Exit check: a test pull request is green. A deliberate lint error makes it red.
A deliberate committed token makes the Betterleaks step red. MegaLinter does not run.

Rollback: one revert that restores the two MegaLinter files and removes `lint.yaml`.

## Phase 3: nightly

1. Add a scheduled workflow with `betterleaks git . --report-format sarif --report-path <file> --redact`.
2. Grant `security-events: write`. Upload with `github/codeql-action/upload-sarif`, SHA pinned.
3. Allow findings without failing the job. Triage the historical findings first.

Exit check: the scheduled run completes and SARIF appears in code scanning.

## Open items

| #   | Item                                                      | Phase | Status     |
| --- | --------------------------------------------------------- | ----- | ---------- |
| 1   | Betterleaks commit-range flags for `git`                  | 2     | To verify  |
| 2   | Betterleaks SARIF flags for `git` (verified for `dir`)    | 3     | To verify  |
| 3   | Entry names for pre-commit-hooks and texthooks from pipx  | 1     | To verify  |
| 4   | Backend for Lucas-C hooks and sops forbid-secrets         | 1     | To verify  |
| 5   | Renovate updates new `.mise.toml` entries                 | 1     | To verify  |
| 6   | Runner has docker compose and PyYAML for the compose hook | 2     | To verify  |
| 7   | Hook output parity against MegaLinter                     | 1     | Exit check |

## Secret scan scope

- Staged mode scans only the staged diff. Unstaged and untracked files are not scanned.
- `prek run --all-files` runs the staged hook. With `pass_filenames: false`, the
  hook still reads only the index. Result: a full run does not scan the tree.
- This is not new. The current gitleaks hook runs `gitleaks git --pre-commit --staged`.
  Tested 2026-11-18 with a committed token: gitleaks scanned about 0 bytes and passed.
  Betterleaks behaves the same.
- Full-tree coverage is not in the current local setup. The MegaLinter
  Betterleaks step may cover it in CI. Not verified.

## Risks

- Remote `rev` pins leave `.pre-commit-config.yaml`. Renovate then tracks the
  `.mise.toml` pins only. Item 5 must pass.
- The PR gate checks changed files. Full-tree checks run on `workflow_dispatch`.
- Staged Betterleaks does not see untracked files. Phase 3 covers full history.
- The first nightly run may show old secrets. Triage them before phase 3 closes.
