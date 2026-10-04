# jarvis

LAN-only Docker host — this machine (`192.168.30.100`, eno1, same subnet as red).
GitOps via doco-cd with `TARGET=jarvis` (`docker/.doco-cd.jarvis.yaml`).

## Services

| Service            | Hostname                 | Backend (target)                            | Direct host port |
| ------------------ | ------------------------ | ------------------------------------------- | ---------------- |
| traefik            | —                        | —                                           | `80`/`443` (LAN) |
| openchamber (host) | `openchamber.tyriis.dev` | Docker-host process `:3000` (file provider) | `:3000` (host)   |

Traefik terminates TLS for proxied routes. It obtains a single wildcard certificate
(`tyriis.dev` + `*.tyriis.dev`) from Let's Encrypt via the Cloudflare DNS-01 challenge
(shared Traefik definition `docker/deploy/traefik/compose.yaml`; the jarvis instance is
an include shim overriding only `command:`/`volumes:` — see `docker/jarvis/traefik/compose.yaml`).

**`openchamber.tyriis.dev` is the one non-Docker backend on this host.** It is served by the
Traefik _file provider_ (`docker/jarvis/traefik/dynamic/openchamber.yaml`): OpenChamber runs as
a host process and Traefik reaches it at `http://host.docker.internal:3000` (host-gateway).
Requirements: the process must listen on a non-loopback address (currently `0.0.0.0:3000`) and
must run with its built-in UI password (`--ui-password`), since raw `:3000` is plain HTTP on
the LAN. Do not port-forward `:3000` — access it via the TLS route.

## First deploy

1. Create the UniFi (UDM SE) local DNS A record `openchamber.tyriis.dev` → `192.168.30.100`.
2. Put the real Cloudflare token (Zone:DNS:Edit on the `tyriis.dev` zone) into the encrypted file: `sops docker/jarvis/traefik/sops.env`, replace `CF_DNS_API_TOKEN=REPLACE_ME`.
3. The age private key is at `~/.config/sops/age/keys.txt`; doco-cd reads the same path via `jarvis.env`. Public key: `age1hpqz0wylrtaf5evn844jkq039wv2cye7cux9gkta9kd5na87yass4yd2k8` (rule in `.sops.yaml`).
4. Create the doco-cd webhook secret file (contents unused unless webhooks are wired up): `mkdir -p ~/.config/doco-cd && openssl rand -hex 16 > ~/.config/doco-cd/webhook_secret`
5. Start the doco-cd agent (polls `main` every 180s, applies `docker/.doco-cd.jarvis.yaml`): `docker compose --project-directory docker/deploy/doco-cd --env-file jarvis.env up -d`
6. Or without GitOps, apply the stack directly: `docker compose --project-directory docker/jarvis/traefik up -d`
7. Ensure the host OpenChamber runs with `--lan --ui-password` and survives reboots if desired.

Verify: `curl -sI https://openchamber.tyriis.dev` serves a valid `*.tyriis.dev` certificate and
redirects HTTP→HTTPS; `docker run --rm --network apps --add-host host.docker.internal:host-gateway
curlimages/curl -sI http://host.docker.internal:3000` proves container→host reachability.

## Notes

- TLS provides transport security only; access control is OpenChamber's own UI password.
- The cert is independent from red's Traefik (separate acme.json in the per-host
  `traefik_config` volume). Both hosts may serve `*.tyriis.dev` — DNS decides which host
  gets which hostname's traffic.
- WebSockets/SSE (terminal, event streams) pass Traefik natively; no extra route tuning needed.
