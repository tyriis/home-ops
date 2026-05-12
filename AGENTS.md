# AGENTS.md

## Skills Setup

This repo uses agent skills tracked in `skills-lock.json`. Skills are not committed to git and must be installed locally.

**Before starting any task**, check if the skills are installed. If `.agents/skills/` is missing or any skill directories listed in `skills-lock.json` are absent, run:

```sh
npx skills install
```
