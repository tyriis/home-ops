# CI: trigger workflows only when their area changes

Issue: [#11770](https://github.com/tyriis/home-ops/issues/11770)

## Intent

Every push and pull request currently starts more work than its diff justifies.
The goal is fewer wasted CI minutes: a gate should start when the files it
validates change, and not otherwise. Correctness gaps found along the way are
fixed in the same pass, because they are one-line edits in the same trigger
blocks.

## Goals

- Stop the heavy `kubernetes` gates from running on PRs that touch no
  Kubernetes manifest.
- Stop starting workflows on events where they cannot produce a useful result.
- Close the existing holes where a real change does *not* start its gate.
- Keep every gate's validation scope exactly as it is today.

## Non-goals

- No restructuring into a single mega-workflow or a shared `changed-files` job.
  The repository has no reusable workflows today and eight files is not worth
  the indirection.
- No change to what any gate validates, to MegaLinter's linter set, or to
  branch protection.
- No path filter on `pr-labeler` or `dependency-review`: both must observe every
  PR. `dependency-review` reads the PR diff itself; `pr-labeler` needs to label
  docs-only and docker-only PRs too.
- No rework of `.github/labeler.yaml` areas. It is a separate taxonomy and
  nothing in CI consumes it.

## Constraints

- The repository is GitOps: no workflow deploys to a cluster, so a wrong filter
  cannot cause a bad deploy. Its cost is a lost validation gate.
- No workflow is a required status check today (owner's answer). A path-filtered
  workflow that does not run therefore cannot block a merge. If one of these is
  ever marked required, it must switch to the always-run-job-with-`paths-filter`
  pattern, because GitHub leaves a skipped required check "Expected" forever.
- Every gate must list the workflow file itself in `paths`, or a change to the
  gate cannot be tested by the gate.
- The runner is self-hosted for Renovate and `ubuntu-latest` elsewhere; minutes
  are the currency, not runner count.

## Approaches considered

**A. Surgical per-workflow `paths:` (chosen).** Repair and narrow the trigger
blocks in the six affected workflow files. Native GitHub syntax, no new
machinery, each file stays self-explanatory. Cost: the same area glob is
repeated where two workflows cover one area (`kubernetes/**` appears in
`flate` and `deadvalues`).

**B. One gate workflow with a `changes` job.** A single workflow, a
`tj-actions/changed-files` job with one key per area, and `if:` on each real
job. One source of truth, and unaffected jobs show as *skipped* rather than
vanishing. Rejected: rewrites eight files into one, loses per-workflow
concurrency groups, and buys nothing at this size — the same globs live in one
place either way.

**C. Areas defined once, filters verified in CI.** A config file listing areas
plus a check that each workflow's `paths:` matches it. Rejected: a new config
format and a new check to maintain, to protect six trigger blocks that change
rarely.

## Design

| Workflow | Today | After |
| --- | --- | --- |
| `deadvalues` | PR on **any** branch, `paths: **/*.yaml` | `branches: [main]`; `paths: kubernetes/**, .deadvalues.yaml, .github/workflows/deadvalues.yaml` |
| `flate` | `paths: kubernetes/**.yaml` | `paths: kubernetes/**, .github/workflows/flate.yaml` |
| `docker` | `paths: docker/**, scripts/hooks/check-docker-compose.sh` | add `.github/workflows/docker.yaml` |
| `MegaLinter` | every PR + every push to `main`, no concurrency | add the standard concurrency block; triggers unchanged |
| `Scorecard` | push to `main` + weekly + `branch_protection_rule` | drop the `push` trigger |
| `Schedule - Renovate` | hourly + push filter that names a non-existent directory | drop `.github/renovate/**.json5`; add a non-cancelling concurrency group so hourly runs queue instead of overlap |
| `Dependency Review` | every PR | unchanged |
| `Pull Request Labeler` | every PR | unchanged |

Rationale for the two glob choices:

- `deadvalues` scans `kubernetes` only (`path: kubernetes`), but its trigger is
  `**/*.yaml`, so a Talos, compose, devenv or workflow YAML PR pays its ~14
  minute run for nothing. This is the bulk of the saving.
- `flate` renders the whole Flux tree. `kubernetes/**.yaml` matches YAML at any
  depth but silently misses the four `.yml` files and the non-YAML assets under
  `kubernetes/`. `kubernetes/**` is both simpler and complete.

MegaLinter keeps unfiltered triggers deliberately: it lints Markdown, YAML and
JSON, so nearly every PR touches a file it would lint, and a filter would be
near-vacuous. Its saving is cancelling superseded runs, not skipping runs.

Dropping Scorecard's `push` trigger is a posture change, not only a saving: the
supply-chain report then refreshes weekly and on branch-protection changes
instead of on every merge. It is advisory, and this matches the upstream
template's minimum.

## Risks

- A file moves into `kubernetes/` from elsewhere (or the reverse) and the globs
  no longer describe the area. Mitigated by using whole-directory globs.
- A new validation script added outside an area's `paths` is not exercised by
  its gate. Mitigated by the `docker` precedent: scripts a gate runs are listed.
- Scorecard results go stale between weekly runs.

## Verification

- `task lint:all` and `pre-commit run --all-files` (actionlint, yamllint,
  prettier) pass.
- Glob sanity: assert with `git ls-files` that every file the gate needs is
  matched by its `paths` entry and that no file outside the area matches.
- Empirical: after merge, a docs-only PR starts only MegaLinter, Dependency
  Review and the labeler; a `kubernetes/` PR starts `flate` and `deadvalues`; a
  `docker/` PR starts `docker` only.

## Left to the builder

- Exact YAML formatting of the `concurrency` block for MegaLinter and Renovate
  (copy the existing three-workflow block; Renovate's uses
  `cancel-in-progress: false`).
- Whether to also add the workflow file itself to `docker`'s paths (design says
  yes).
