# docker

The Docker hosts that run outside Kubernetes. They hold what needs hardware the clusters do not have
(GPUs, large disks, USB devices) or what must survive a Talos upgrade without a scheduler.

This file documents what is true for every host in this directory. Host-specific documentation lives in
Backstage as a **System** per host (`bifrost`, `nas`, `synology-nas`), with the services running on it as
**Components** of that system.

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

## Delivery

[doco-cd](https://github.com/kimdre/doco-cd) polls `main` every 180 s and applies the stacks listed in
`.doco-cd.<host>.yaml`. There is no push step and no manual `docker compose up` in normal operation.

A stack removed from a deploy config keeps running: doco-cd does not tear down what it no longer tracks. See [Offboarding a service](#offboarding-a-service).

## Offboarding a service

Order matters. Removing the container before its monitoring leaves a scrape job pointing at nothing, which produces `up == 0` and fires `HostScrapeFailing` after ten minutes. Work top to bottom.

1. **Monitoring first.** Drop the job from `docker/<host>/vmagent/scrape.yaml`, delete the endpoint from the Gatus config, and remove any alert rule keyed on that job name.
2. **DNS.** Delete the record in `techtales-io/terraform-unifi`. Nothing in this repository owns DNS, so this is the step most often forgotten, and it leaves a name resolving to a host that no longer serves it.
3. **Deploy config.** Remove the stack from `docker/.doco-cd.<host>.yaml`, then delete the host directory and the shared blueprint in `docker/deploy/` if nothing else includes it.
4. **On the host.** Run `docker compose --project-directory docker/<host>/<service> down -v`. The `-v` matters: doco-cd never removes volumes, and an orphaned named volume is silent disk growth.
5. **Networks.** Leave the shared `apps` network alone. Check `docker network inspect apps` before removing anything; other stacks attach to it.
6. **Secrets.** Delete the stack's `.env` and `sops.env`, and remove the matching entries from OpenBao if the Kubernetes side read them.

Auto-discovery would handle step 3's teardown automatically, but no host enables it, and `auto_discovery.delete` defaults to false even when it is on.

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

Three rules follow, and breaking any of them fails quietly:

1. **`project_directory: .` is required.** Without it, relative paths inside the shared blueprint (`env_file`, bind mounts) resolve against `docker/deploy/` instead of the host directory.
2. **Symlinks are banned.** They resolve technically but cause redeploy-hash churn (doco-cd #954) and path-escape false positives (v0.74 regressions #1142/#1086/#1152).
3. **List fields are replaced, not appended.** Compose replaces `command:` and `volumes:` from an include, so a host that needs one extra flag must re-list the whole field.

`name:` in the deploy config stays equal to the service name even after `working_dir` moves, so the compose
project — and therefore the running containers — survive the move instead of being recreated under a new
name.

## Secrets

Encrypted values live in `sops.env` with a per-host age recipient (`.sops.yaml`). doco-cd decrypts those
files in place at deploy time; `env_files` in the deploy config also make the values available for `${VAR}`
interpolation in compose.

Application services take credentials as environment variables. doco-cd itself uses compose `secrets:` with
file sources for its age key and webhook secret. Whether app services should follow is open: `secrets:
environment:` keeps the value out of `docker inspect`, and it is not done yet because a misspelled `*_FILE`
variable fails silently rather than refusing to start.

## Invariants

Enforced by review, not by tooling:

- **No inbound scrape or admin port.** Exporters and agent endpoints bind `127.0.0.1` in the container and
  are scraped by the host's own vmagent. The only LAN-facing ports are Traefik's `80`/`443` and services
  deliberately published for LAN use.
- **Bounded logs.** Every service carries a `json-file` block with `max-size: 10m`, `max-file: "3"` and the
  label list VictoriaLogs ships as attributes. It lives in the shared blueprint, so a new host inherits it.
- **One egress, one token.** vmagent remote-writes to the central VictoriaMetrics store through vmauth; no
  host accepts inbound metrics traffic.
- **Images are digest-pinned.** Renovate raises the bumps; nothing applies automatically.

## Monitoring

Each host runs `vmagent` (metrics, remote-write) and `victoria-logs-collector` (logs, tailing container json
files plus the host's own syslog). Alerts are evaluated centrally by vmalert; route availability is probed
by Gatus.

Two blind spots are known and deliberate:

- **A dead vmagent is silent.** `HostScrapeFailing` needs an `up` series at 0, and a dead vmagent writes no
  series at all; the fleet-level `absent()` rule is satisfied by the other always-on hosts.
- **Workstations are off by policy.** `red`, `purple`, `hades`, `coal` and `carbon` are excluded from the
  host-down rules, so their failures do not page.

## Editing files here

The repository's comment policy says comments are anchors, not documentation. In this directory that means:

- **Edit-time constraints stay inline**, one line, next to what they constrain — the `project_directory: .`
  requirement in a shim, or the fact that compose replaces list fields.
- **Everything else belongs here or on the host's Backstage page.** A repeated header block drifts; this
  file does not.

## Known exceptions

- **sparkDash on bifrost runs outside this repository** — no compose file, no digest pin, no update path.
- **`coal` has no host directory.** It deploys `docker/deploy/node-exporter` directly, which is why its
  smartctl exporter has no device whitelist.
- **Synology's smartctl exporter was disabled** (`ENABLE_SMARTCTL_EXPORTER=0`) until 2026-11, so its disk
  health was absent from the central store before then.
