---
status: accepted
date: 2026-05-12
decision-makers: [tyriis, Jazzlyn]
---

# External agent skills are not committed to git

## Context and Problem Statement

Agent skills from third-party sources (e.g. `fluxcd/agent-skills`) were committed to the repository under `.agents/skills/`.
This couples the repo to a specific snapshot of externally maintained content and pollutes git history with large file sets that are not owned by this project.

## Decision Drivers

- Skills maintained by others should not be versioned in this repo
- `skills-lock.json` already provides a reproducible install manifest
- New contributors need a clear, automated path to install skills

## Considered Options

- **Option 1:** Keep external skills committed to git
- **Option 2:** Gitignore `.agents/skills/` and install via `npx skills install`

## Decision Outcome

Chosen option: **Gitignore `.agents/skills/` and install via `npx skills install`**

External skills are excluded from git via `.gitignore`. The `skills-lock.json` file remains the source of truth for which skills
are required and at what version. `AGENTS.md` instructs agents to run `npx skills install` if skills are absent.
Self-maintained skills can be opted back into git with a gitignore negation.

### Consequences

- **Good, because** git history is not polluted with third-party content.
- **Good, because** skill updates are decoupled from repository commits.
- **Good, because** `skills-lock.json` ensures reproducible installs.
- **Bad, because** contributors must run `npx skills install` after a fresh clone.
