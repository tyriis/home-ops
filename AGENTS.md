# AGENTS.md

## CRITICAL — MANDATORY FIRST ACTION (NO EXCEPTIONS)

**BEFORE doing anything else — before reading files, asking questions, or starting any task — run this command:**

```bash
ls .agents/skills/ 2>/dev/null || npx skills experimental_install
```

Do NOT proceed until this has been executed and confirmed.

After skills are installed, ask the user to restart the coding assistant.

## Section 1: Core Directives & Rules

### BRANCH_NAMING

- Branch names MUST be `<bugfix|feature>/<kebab-case-name>`, max 40 chars.
- `bugfix/` = bugfix, `feature/` = feature — NEVER `fix/`, `hotfix/`, `chore/`, or bare names.
- This applies to every branch created in this repo, including one-off agent/PR branches.

### RESPONSES

- Keep responses concise and to the point - unless the user asks otherwise.

### PLANNING_MODE

- Always ask clarifying questions.
- Never assume design, tech stack or features.
- Use deep-dive sub-agents to assist with research and to review different aspects of your plan before presenting to the user.

### CHANGE_EDIT_MODE

- Never implement features yourself when possible - use sub-agents.
- Identify changes from the plan that can be implemented in parallel, and use sub-agents to implement the features efficiently.
- When using sub-agents to implement features, act as a coordinator only.
- Use the best model for the task.

### GIT_COMMIT

- Use `git-commit` skill for all git commit messages.

### SUBAGENT_DEVELOPMENT

When using the `writing-plans` skill to generate an implementation plan or when writing specs:

- **Git Commits in Plans**: Ensure the git commit commands specified in the plan STRICTLY follow the `GIT_COMMIT` rules.
- **Spec Flexibility for Linters/Types**: Explicitly include a note in your plan that the implementer subagent is **authorized and expected** to add necessary type hints, docstrings, linting suppression comments,
  and repository configuration updates required to pass the project's CI, type-checkers, and linters.

### GITOPS_FIRST

When asked to deploy a new application or change a configuration, modify the Flux manifests (HelmReleases, Kustomizations) rather than applying changes directly to the cluster. Manual `kubectl apply` commands should be avoided.

## COMMENTS

Comments are ANCHORS, not documentation. They mark things that need attention or encode constraints a reader cannot derive from the file itself. When in doubt, omit the comment.

### ALLOWED (the only four uses)

1. **Anchors for attention** — `# TODO: <actionable next step>`, `# FIXME: <known breakage>`, `# HACK: <workaround + why>`. One line, actionable, no essays.
2. **Cross-file / cross-system constraints** — a value that must stay in sync with something outside this file. State the coupling inline: `scrapeInterval: 1m # must match interval in Grafana Helm chart`, `prune: false # should never be deleted`.
3. **Non-obvious side effects / traps** — enabling X breaks Y, order matters, a default is dangerous. The cost of silence is a future wrong edit.
4. **Provenance refs** — `# Ref: <url>` pointing at the upstream source of a rule, chart default, or borrowed block. Link only, do not restate the content.

### FORBIDDEN

- Restating what the code/manifest already says (`# creates the namespace` above a Namespace — noise).
- Explaining _why_ a change was made — that belongs in the commit message, not the file.
- Section dividers, banner art, decorative rules.
- Narrative "what this file does" headers — directory layout and filenames already say it.
- Commented-out YAML kept "just in case" — delete it; git remembers.

### RULES

- **Never author or rewrite comments inside vendored/upstream default configs** (e.g. plugin `config.yml` shipped by upstream). They are upstream's; leave them untouched, including their style.
- Prefer NO comment over a weak one. A file with zero comments is not under-documented.
- Never add comments to satisfy a perceived "should be documented" instinct. This repo is manifests and config; git history is the documentation layer.

## Section 2: Repository Architecture & Directory Mapping

### CLUSTER_TOPOLOGY

The infrastructure is split into multiple clusters:

- `kubernetes/main/apps`: Core applications like media, home automation, databases, AI, gaming.
- `kubernetes/utility/apps`: Infrastructure services like Harbor, OpenBao, cert-manager.
- `kubernetes/base` & `kubernetes/components`: Shared kustomizations.

### INFRASTRUCTURE_OS

Kubernetes nodes are running Talos Linux.

- `talos/main` & `talos/utility` contain the machine configurations and cluster configurations.

### TOOLING_AUTOMATION

All automation and scripts are managed via Task. Always use `task` to execute workflows. You can discover available tasks by running `task --list` or exploring the `.taskfiles/` directory. Do not write custom bash scripts for standard operations.

### LOCAL_DEVELOPMENT

The `devenv/` directory contains configurations for a local docker/kind environment used for testing.

## Section 3: Secret Management, App Scaffolding, & Quality

### SECRET_MANAGEMENT

- **Primary**: The vast majority of secrets are stored in OpenBao and synced to the clusters using the External Secrets Operator (`ExternalSecret` manifests).
- **Secondary**: SOPS (with age encryption) is used sparingly, primarily for bootstrapping the cluster (`talos/` configs).

### CRITICAL-SECURITY

Never commit plaintext secrets to the repository.

### APP_SCAFFOLDING

Use read and glob tools to understand how similar applications are deployed before scaffolding a new application. Strictly follow the existing structural conventions and directory layout.
When adding a new app, always copy the structure of an existing app in `kubernetes/main/apps/` (e.g., check `podinfo` or `echo-server` in the `default` namespace).
This includes `kustomization.yaml`, `namespace.yaml`, and the release manifest (like `helmrelease.yaml`).

### QUALITY_VERIFICATION

- Tooling versions are strictly managed using `mise` (`.mise.toml`).
- This repository uses `pre-commit` and MegaLinter. Ensure changes are properly formatted and pass linting before committing.

### REGRESSION INVESTIGATION

When investigating a bug or regression, first check recent git history (last 20-30 commits)
on the affected area to identify what changed. If the user says "it worked before",
correlate the timeline of recent changes immediately before deep-diving into code/config.

### PR WORKFLOW

After committing and pushing a fix/feature to a branch:

1. Present the commits to the user and ask if they're aligned/happy with the changes.
2. Ask: "Ready for a PR?" — do not create a PR without confirmation.
3. **MERGING**: When instructed to merge a PR, YOU MUST ONLY use the `task git:pr-merge -- <PR_NUMBER>` task. NEVER use `gh pr merge --squash`. Squashing is strictly forbidden and breaks repository history.

### POST-MERGE CLEANUP

When the user says "I merged it" or equivalent, automatically:

1. `git checkout main`
2. `git pull`
3. `git fetch -p`
4. Delete all dangling local branches (`git branch -vv | awk '/: gone]/{print $1}' | xargs -r git branch -D`)
