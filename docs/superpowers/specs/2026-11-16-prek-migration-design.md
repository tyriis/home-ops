# prek migration: replace MegaLinter and pre-commit

Issue: [#10151](https://github.com/tyriis/home-ops/issues/10151)

Status: draft. Not committed. Awaiting approval.

## Intent

The repository runs two linting systems. MegaLinter runs in CI. pre-commit runs
locally. They overlap, and CI spends most of its time pulling a 1.41 GB Docker
image. One tool, prek, runs the same hooks locally and in CI. The same config
file defines both.

Measured baseline: MegaLinter job takes 70 to 100 seconds. About 65% is the
Docker pull.

## Goals

- prek runs every hook locally, in the `pre-commit` and `pre-push` stages.
- prek runs the same hooks in CI on each pull request (`opened`, `reopened`, `synchronize`).
- Betterleaks replaces gitleaks in the local hook set and in the nightly scan.
- Hook coverage matches the eight MegaLinter linters: actionlint, prettier
  (JSON and YAML), markdownlint, yamllint, editorconfig-checker, betterleaks,
  and proselint.
- CI warm run takes about 15 to 25 seconds.

## Non-goals

- No inline pull request annotations. CI output is log-only. The owner accepted
  this trade-off.
- No `flux-check-hook`. It is removed and will not be added again.
- No self-hosted runner and no custom image with a pre-warmed `PREK_HOME`. These
  are deferred. Revisit only if cold starts are a problem.
- No change to hook behavior beyond what parity requires.
- No edits to vendored or upstream config content.

## Constraints

- Go-based hooks must not compile from source on each cold run. A cold compile
  takes 2 to 4 minutes. Run Go-based tools with prek's `language: mise` and
  aqua prebuilt binaries.
- Betterleaks latest stable release is v1.10.1 (published 2026-11-12). The
  `main` branch is v2 development, and v2 is not yet a stable release. Pin
  v1.10.1 for phases 1 and 2. Move to v2 later, following the v2 migration guide.
- The repository already has a `.gitleaksignore` file. Betterleaks reads it
  without change. Any gitleaks config file is migrated to Betterleaks
  configuration.
- Betterleaks ships an official pre-commit hook (`betterleaks`). The `betterleaks`
  hook builds from source. Do not use it. Define the hook locally with
  `language: mise` and the aqua binary, to match the Go-hook constraint.
- Version pins follow the repository rule: tool versions live in `.mise.toml`.
- Workflow files follow the existing hardening pattern: pinned action SHAs and
  `harden-runner`, as in `.github/workflows/mega-linter.yaml`.
- No workflow in this repository is a required status check today. A skipped
  or failing lint job does not block a merge.

## Approaches

**A. Phased migration (chosen).** Phase 1 makes the local command work. Phase 2
switches CI. Phase 3 adds the nightly Betterleaks scan with SARIF output. Each
phase has its own exit check. A problem in one phase does not block the others.

**B. Big-bang switch.** Replace local tooling, CI, and nightly scan in one
change. Rejected: harder to review, and a failure blocks every lint path at once.

## Phase 1: local command

1. Install prek with `mise` in `.mise.toml`.
2. Convert `.pre-commit-config.yaml` to `prek.toml` with
   `prek util yaml-to-toml`. Delete the YAML file. The conversion drops YAML
   comments, so re-check the repo's remaining comments by hand.
   prek does not discover `.prek.toml`. Use `prek.toml`.
3. Replace the gitleaks hook with a local Betterleaks hook (`language: mise`).
4. Add editorconfig-checker and proselint hooks, with `language: mise` where
   they are Go tools.
5. Keep the existing hook set. Keep both `pre-commit` and `pre-push` stages.
6. Update the task entry points: `.taskfiles/pre-commit/Taskfile.yaml` and the
   `pre-commit` calls in `.taskfiles/devenv/Taskfile.yaml`. Use prek commands in
   place of `pre-commit` commands. Keep the task names stable where possible.
7. Update `AGENTS.md` (line 125) and the README pre-commit references.

Exit check: `prek run --all-files` exits 0 on the current tree. Hook output
matches MegaLinter results on the same tree, or each difference is explained.

## Phase 2: CI

1. Add `.github/workflows/lint.yaml`.
   - Trigger: `pull_request` with types `opened`, `reopened`, `synchronize`.
     No push trigger.
   - Run: `prek run --from-ref <base.sha> --to-ref <head.sha>`.
   - `workflow_dispatch`: `prek run --all-files`, for manual full runs.
2. Use `j178/prek-action` with a cached `PREK_HOME`. Pin the action to a SHA.
3. Add `harden-runner`, matching the existing workflow pattern.
4. Apply the `github-actions-hardening` and `github-actions-efficiency` skills
   to the new workflow before it is merged.
5. Delete `.github/workflows/mega-linter.yaml` and `.mega-linter.yaml`.
6. Update the MegaLinter badge in `README.md`.

Exit check: a test pull request runs `lint.yaml` green. A deliberate lint error
makes it red. The MegaLinter workflow no longer runs.

## Phase 3: nightly Betterleaks scan

1. Add a scheduled workflow that runs a full-history Betterleaks git scan.
2. Emit SARIF and upload it to GitHub code scanning.
3. Verify the Betterleaks SARIF flag and the upload path before implementation.
   The official GitHub Action for Betterleaks is third-party. Use the CLI
   directly unless a reviewed action exists.

Exit check: the scheduled run completes. SARIF appears in code scanning.

## Open items for implementation

- Confirm the `mise` backend provides `betterleaks`, `actionlint`, and the
  other Go tools used by the hooks, and the exact `additional_dependencies`
  syntax for each.
- Confirm the proselint and editorconfig-checker hooks match MegaLinter settings
  (`.editorconfig` and the proselint rule set).
- Confirm the Betterleaks SARIF output flag at v1.10.1.

## Decisions taken

- Betterleaks replaces gitleaks in local hooks and nightly scan.
- Go-based hooks use prek's `language: mise`.
- The config file is `prek.toml`. The dot-prefixed `.prek.toml` is not a supported name.
- CI runs on pull request events only: `opened`, `reopened`, `synchronize`.
- Log-only CI output.
- No `flux-check-hook`.
- Phase order: local, CI, nightly.
