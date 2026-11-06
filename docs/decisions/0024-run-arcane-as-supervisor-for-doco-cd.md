---
status: accepted
date: 2026-11-07
decision-makers: [tyriis]
---

# Run Arcane as the supervisor that deploys doco-cd

## Context and Problem Statement

doco-cd deploys every stack on the Docker hosts. It polls the repo every 180 s
and applies changes, including image tag bumps. One stack is excluded from its
own scope: doco-cd never recreates itself, and `SELF_UPDATE_ENABLED` stays
`false`. A container that updates itself is its own only recovery path — a bad
config would wedge the deployer on every host at once with nothing left outside
to undo it.

That leaves every doco-cd self-bump in an awkward state. The PR merges, the
config lands, and no host moves: doco-cd on the hosts keeps running the old
image because the only tool that could apply the change is the tool the change
is about. The 0.132.0 bump sat undeployed on two hosts for days, and during
that window three hosts were broken and silent — the gap PR #11764's scrape
work now closes. Redeploying by hand (a human pastes `docker compose up -d`
per host) works but records nothing and is easy to forget.

## Considered Options

- **doco-cd self-update.** Rejected: the circularity above. Also, a deployer
  mid-recreate cannot observe its own failure — the "polls stay at zero diff"
  check would be self-reported by the component it verifies.
- **Manual re-up per host.** Kept as the emergency path only. No record, no
  cadence, and it does not scale past a few hosts.
- **Arcane as the supervisor (chosen).** Arcane is already adopted for the
  update path. Making it the owner of the doco-cd container gives the
  deployer an outer deployer. Arcane never updates itself either — a separate
  decision we already accept, because Arcane's recovery path is a container
  restart, not a config-sync loop.

## Decision Outcome

Chosen: **Arcane owns the lifecycle of the doco-cd container on the Docker
hosts.** Concretely:

- The doco-cd container is created and recreated by Arcane projects, not by
  doco-cd and not by ad-hoc `compose up` on the host.
- doco-cd's own stack config keeps doco-cd excluded from its target file.
  The exclusion is the design, not an omission.
- Self-bump PRs (image tag changes to `docker/deploy/doco-cd/compose.yaml`)
  are "dormant until Arcane applies them" — the rollout checklist for those
  PRs tracks Arcane projects, not doco-cd polls.
- Synology proves the shape end-to-end: a dedicated bootstrap directory
  (`docker/synology/doco-cd/`, PR #11767) that Arcane consumes, with
  host-local files under `/etc/doco-cd/` staying host-local.

Consequences, honest ones:

- Adoption is partial and deliberate: bifrost and truenas run it fully
  automatic via Arcane git-sync; red, purple and synology deploy through
  Arcane on operator trigger; jarvis and agentix still take manual re-ups.
  Converging them is migration work, not an open question.
- The chain now has two deployers, so both need eyes. `up{job="doco-cd"}`
  from PR #11764 covers the deployer's health; the same scrape pattern
  applies to Arcane on each host.
- `compose down` on a host where Arcane owns the project is now a
  cross-tool deletion. The data volume names are shared, so the old
  never-`down` rule (`docker rm -f <name>`, volume preserved) applies to
  both tools.

## More Information

- PR #11764 (scrape + alert for both shippers, this fleet's verification
  layer), PR #11767 (synology bootstrap under Arcane), issue #11602.
- Rollout report with the 7-host table:
  <https://github.com/tyriis/home-ops/pull/11764#issuecomment-6698239473>
