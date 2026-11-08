# System: docker-fleet

The Docker hosts that run outside Kubernetes. They hold anything that needs hardware the clusters do not
have (GPUs, large disks, USB devices) or that has to survive Talos upgrades without a scheduler.

Eight hosts, one delivery mechanism, one compose pattern:

| Host       | Role                                      | Deploy config            |
| ---------- | ----------------------------------------- | ------------------------ |
| `agentix`  | agent host (hindsight, arcane edge agent) | `.doco-cd.agentix.yaml`  |
| `bifrost`  | LLM gateway (`new-api`), sparkDash        | `.doco-cd.bifrost.yaml`  |
| `coal`     | laptop, rarely online                     | `.doco-cd.coal.yaml`     |
| `jarvis`   | LAN-only host (OpenChamber, Hermes)       | `.doco-cd.jarvis.yaml`   |
| `purple`   | GPU workstation                           | `.doco-cd.purple.yaml`   |
| `red`      | GPU workstation                           | `.doco-cd.red.yaml`      |
| `synology` | DSM NAS                                   | `.doco-cd.synology.yaml` |
| `truenas`  | NAS, backup target                        | `.doco-cd.truenas.yaml`  |

Each host has its own page under `systems/<host>/` with hardware, services and runbooks. This page holds
what is true for all of them.

## Delivery

[doco-cd](https://github.com/kimdre/doco-cd) polls `main` every 180 s and applies the stacks listed in
`docker/.doco-cd.<host>.yaml`. There is no push step, no CI deploy and no manual `docker compose up` in
normal operation. A stack that is removed from a deploy config keeps running: doco-cd does not tear down
what it no longer tracks, so offboarding a service needs an explicit `docker compose down -v` on the host.

## Layout

```text
docker/
  deploy/<service>/compose.yaml   shared blueprint, digest-pinned image
  <host>/<service>/compose.yaml   host shim: include + host-only overrides
  <host>/<service>/.env           plain values (TARGET, ports, ACME_EMAIL)
  <host>/<service>/sops.env       SOPS-encrypted secrets, committed
  <host>/vmagent/scrape.yaml      per-host scrape targets
  .doco-cd.<host>.yaml            the stacks that host runs
```

## The include-shim contract

A host shim is a real file, never a symlink:

```yaml
---
include:
  - path: ../../deploy/<service>/compose.yaml
    project_directory: .
```

Three rules follow from this, and breaking any of them fails quietly:

1. **`project_directory: .` is required.** Without it, relative paths inside the shared blueprint (`env_file`, bind mounts) resolve against `docker/deploy/` instead of the host directory.
2. **Symlinks are banned.** They resolve technically but cause redeploy-hash churn (doco-cd #954) and path-escape false positives (v0.74 regressions #1142/#1086/#1152).
3. **List fields are replaced, not appended.** Compose replaces `command:` and `volumes:` from an include, so a host that needs one extra flag must re-list the whole field.

`name:` in the deploy config stays equal to the service name even after `working_dir` moves, so the compose
project — and therefore the running containers — survive the move without being recreated under a new name.

## Secrets

Everything encrypted lives in `sops.env` with a per-host age recipient (`.sops.yaml`). doco-cd decrypts
those files in place at deploy time; `env_files` in the deploy config also make the values available for
`${VAR}` interpolation in compose.

Application services take credentials as environment variables. `doco-cd` itself uses compose `secrets:`
with file sources for its age key and webhook secret. Whether app services should follow is an open
question: `secrets: environment:` would keep the value out of `docker inspect`, and it is deliberately not
done yet because a misspelled `*_FILE` variable fails silently.

## Invariants

These are enforced by review, not by tooling:

- **No inbound scrape or admin port.** Exporters and agent endpoints bind `127.0.0.1` in the container and
  are scraped by the host's own vmagent. The only LAN-facing ports are Traefik's `80`/`443` and the
  services deliberately published for LAN use.
- **Bounded logs.** Every service carries a `json-file` block with `max-size: 10m`, `max-file: "3"` and the
  label list that VictoriaLogs ships as attributes. It lives in the shared blueprint, so a new host
  inherits it.
- **One egress, one token.** vmagent remote-writes to the central VictoriaMetrics store through vmauth; no
  host accepts inbound metrics traffic.
- **Images are digest-pinned.** Renovate raises the bumps; nothing is applied automatically.

## Monitoring model

Each host runs `vmagent` (metrics, remote-write) and `victoria-logs-collector` (logs, tailing the container
json files and the host's own syslog). Alerts are evaluated centrally by vmalert; route availability is
probed by Gatus.

Two blind spots are known and deliberate:

- **A dead vmagent is silent.** `HostScrapeFailing` needs an `up` series at 0, and a dead vmagent writes no
  series at all; the fleet-level `absent()` rule is satisfied by the other always-on hosts.
- **Workstations are off by policy.** `red`, `purple`, `hades`, `coal` and `carbon` are excluded from the
  host-down rules, so their failures do not page.

## Editing these files

The repo's comment policy says comments are anchors, not documentation. For this directory that means:

- **Edit-time constraints stay inline**, one line, next to the thing they constrain — for example the
  `project_directory: .` requirement in a shim, or the fact that compose replaces list fields.
- **Everything else lives on this page or the host's page.** A shim's header comment should be at most a
  pointer, because the same explanation repeated in 35 files drifts.

## Known exceptions

- **sparkDash on bifrost runs outside this repository** — no compose file, no digest pin, no update path.
  Its runbook is on the bifrost page.
- **`coal` has no host directory yet.** It deploys `docker/deploy/node-exporter` directly, which is why its
  smartctl exporter has no device whitelist.
- **Synology's smartctl exporter was disabled** (`ENABLE_SMARTCTL_EXPORTER=0`) until 2026-11, so its disk
  health was not in the central store before then.
