# System: bifrost

The `bifrost` system is an Intel N250 mini-server. Purpose: **LLM API gateway** (new-api) and **sparkDash host** (monitoring for the DGX Sparks).

It is **LAN-only** — Tailscale is deliberately not deployed on this host — and runs **LightWale OS** (Buildroot-based, busybox init, **no systemd**): services are managed with `/etc/init.d/S*NN` scripts, so there is no `systemctl`.

## What it hosts

- **new-api** — LLM API gateway ([ai.techtales.io](https://ai.techtales.io), port `3000`).
- **traefik** — LAN reverse proxy on `80`/`443`.
- **sparkDash** — DGX Spark monitoring dashboard (port `8080`).

## Deployment

Deployed via **doco-cd** from `docker/bifrost/` in this repository: each service directory holds a thin compose
**include shim** that pulls the shared service definition from `docker/deploy/<svc>/compose.yaml`, so host-relative
paths (`env_file`, bind mounts) resolve against the host directory.

## Documentation

- [Runbook: DNS resolution of local domains](runbooks/dns-lightwale-local-domains.md) — containers fail to resolve `*.techtales.io` names.
