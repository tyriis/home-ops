# bifrost

ASUS NUC 14 Essential (Intel N250) mini-server. Purpose: **LLM API gateway** (new-api) + **sparkDash host** (monitoring for
the DGX Sparks).

**LAN-only** — Tailscale is deliberately **not deployed** on this host until the tailnet decision
is made (see [Future: tailnet + YubiKey ssh-agent](#future-tailnet--yubikey-ssh-agent)).

## Services

| Service   | Host port   | Deploy config           | Compose                                                      |
| --------- | ----------- | ----------------------- | ------------------------------------------------------------ |
| new-api   | `3000`      | `.doco-cd.bifrost.yaml` | `deploy/new-api` (digest-pinned image)                       |
| traefik   | `80`/`443`  | `.doco-cd.bifrost.yaml` | `deploy/traefik` (tag-pinned image, bifrost include shim)    |
| sparkDash | `8080`      | `.doco-cd.bifrost.yaml` | `deploy/sparkdash` (built from local clone — see its README) |
| arcane    | — (Traefik) | `.doco-cd.bifrost.yaml` | `deploy/arcane` (digest-pinned image)                        |

Per-service layout: each service dir holds a **real** thin `compose.yaml` **include shim** plus its
host state. The shim `include:`s the shared service definition from `docker/deploy/<svc>/` with
`project_directory: .`, so relative paths inside the shared compose (`env_file`, the sparkDash
build context, the `./data` / `./config` / `./keys` binds) resolve against this host directory,
not the deploy dir. Why a shim: doco-cd runs compose in `working_dir` and hard-fails with
"no compose files found" unless a compose file is resolvable there. **Symlinks into the working
dir are intentionally avoided** — they resolve technically but are a known source of redeploy-hash
churn (doco-cd #954) and path-escape false positives (v0.74 regressions #1142/#1086/#1152); the
older hosts (synology/truenas) still use symlinks but are out of scope for migration.

`.env` holds plain values (`TARGET`, ports), `sops.env` holds sops-encrypted secrets (committed
placeholders here must be replaced with real sops-encrypted files before first deploy:
`sops docker/bifrost/<svc>/sops.env`).

## Deploy

doco-cd on bifrost polls this repo with `target: bifrost` (`TARGET=bifrost` in each service `.env`) and
applies `docker/.doco-cd.bifrost.yaml`. Before the first deploy:

1. Clone + pin the sparkDash source on the host (doco-cd never pulls it — it is gitignored):

   ```bash
   git clone https://github.com/MiaAI-Lab/sparkDash.git docker/deploy/sparkdash/sparkDash
   git -C docker/deploy/sparkdash/sparkDash checkout cc44d3527e7d
   ```

2. Provision SSH keys on the Sparks (below) and place the private key at
   `docker/bifrost/sparkdash/keys/id_ed25519` (**mode 0600**, gitignored).
3. Seed `docker/bifrost/sparkdash/config/sparks.json` from the skeleton in `docker/deploy/sparkdash/`
   (replace the PLACEHOLDER IPs) or just add units through the sparkDash UI.
4. new-api first deploy (before the service starts):
   - `.sops.yaml` has the bifrost creation rule (`docker/bifrost/.*/sops\.env$`); the matching
     **private** age key must be present in bifrost's doco-cd keyfile (`/etc/doco-cd/age-keys.txt`)
     or doco-cd cannot decrypt `sops.env` at deploy time.
   - On the bifrost host, the data volume must be owned by the service UID (Docker creates
     named volumes root-owned; UID 1001 could not write it otherwise):

     ```bash
     docker volume create new-api_data
     docker run --rm -v new-api_data:/data alpine chown 1001:1001 /data
     ```

   - `WEB_HOST=0.0.0.0` publishes the port on **all bifrost interfaces** (LAN-reachable).
     Because the setup endpoint is unauthenticated until the admin account exists, complete
     the web setup wizard **immediately** on first boot from a trusted machine, enable 2FA,
     and restrict port 3000 with a host firewall allow-list.
5. traefik first deploy (before the service starts):
   - Set the Let's Encrypt registration email in `docker/bifrost/traefik/.env`
     (uncomment `ACME_EMAIL=`) — compose fails fast until it is provided.
   - Replace the sops placeholder with the real Cloudflare DNS API token (Zone:DNS:Edit,
     scoped token — same age-keyfile requirement as new-api above):

     ```bash
     mise exec -- sops docker/bifrost/traefik/sops.env
     ```

   - Pre-create the ACME store on the host — a bind-mounted file target that does not exist
     is created as a **directory** by Docker and traefik then fails to start (gitignored
     runtime state, holds the ACME account private key — never commit it):

     ```bash
     mkdir -p docker/bifrost/traefik/certs && touch docker/bifrost/traefik/certs/acme.json
     chmod 600 docker/bifrost/traefik/certs/acme.json
     ```

   - `WEB_IP=0.0.0.0` publishes 80/443 on all bifrost interfaces (LAN reverse proxy).
6. arcane first deploy (before the service starts):
   - `docker/bifrost/arcane/sops.env` holds a SOPS-encrypted `ENCRYPTION_KEY` (32 bytes) that doco-cd decrypts at deploy time using bifrost's age keyfile (`/etc/doco-cd/age-keys.txt`) — the same requirement as new-api/traefik.
   - No manual volume chown is needed (unlike new-api): Arcane starts as root and chowns `/app/data` to
     `PUID`/`PGID` (1000:1000) before dropping privileges. Do not add `cap_drop`/`user:`/`read_only:` to the
     Arcane service — the startup chown/drop requires `CAP_CHOWN`/`CAP_SETUID`/`CAP_SETGID`.
   - The Traefik Cloudflare DNS token must be extended to the `techtales.io` zone so the `arcane.techtales.io` certificate can be issued (DNS-01).
   - Traefik serves the UI at `https://arcane.techtales.io` (LAN-only). First login is `arcane` / `arcane-admin`;
     change it immediately and enable 2FA. The Docker socket is mounted read-write, so this UI is
     root-equivalent on the host — never expose it beyond the LAN.
7. Let doco-cd deploy (or `docker compose up -d` in a service dir for a manual test).

## SSH key provisioning on the DGX Sparks

sparkDash monitors the Sparks as **remote units** (`isLocal: false`) over SSH.

On **bifrost**, generate one monitoring key (reused for all Sparks):

```bash
ssh-keygen -t ed25519 -N "" -C "sparkdash@bifrost" -f docker/bifrost/sparkdash/keys/id_ed25519
chmod 600 docker/bifrost/sparkdash/keys/id_ed25519
```

> ⚠️ **The key MUST be passphrase-less.** sparkDash invokes `ssh -o BatchMode=yes`
> (`server/collectors/ssh.js`); there is no TTY, so a passphrase prompt can never be answered and
> auth fails silently. Passphrase protection is instead achieved via source-pinning + `restrict`
> (and later the YubiKey/ssh-agent upgrade below).

On **each Spark**, create a dedicated low-privilege user and install the public key:

```bash
# on the Spark
sudo adduser --disabled-password --gecos "" sparkdash
sudo -u sparkdash mkdir -m 700 ~/.ssh
sudo -u sparkdash tee -a ~/.ssh/authorized_keys
# paste: restrict,from="192.168.1.<BIFROST_LAN_IP>" <contents of id_ed25519.pub>
sudo -u sparkdash chmod 600 ~/.ssh/authorized_keys
```

`restrict` strips PTY/port-forwarding/etc., and `from="192.168.1.<BIFROST_LAN_IP>"` pins the key to
bifrost's LAN address — a stolen key is useless from any other source IP. sparkDash only needs plain
exec (metrics commands + `echo ok` tests), which `restrict` allows.

Notes:

- SSH must listen on the **default port 22** on the Sparks — sparkDash's unit schema has no
  per-unit SSH-port field.
- sparkDash connects as the unit's `ssh.user` (`sparkdash` in `config/sparks.json`).

## LAN exposure / LLM binding

The sparkDash API is **unauthenticated by design**; the new-api gateway is not — it has an admin web
UI with login, a token-authenticated relay API, built-in rate limiting and optional 2FA. Keep both
on the trusted LAN only (host firewall; do not forward these ports). LLM servers on the Sparks should be
bound to the **LAN interface** (`llama-server --host 192.168.1.<spark-ip> ...`), not `0.0.0.0`, and
firewalled to bifrost — sparkDash's LLM probes hit the unit LAN IP, and gateway traffic only comes
from bifrost.

## Future: tailnet + YubiKey ssh-agent

Out of scope for now (intentionally no tailscale container on this host):

- Join bifrost (and the Sparks) to the tailnet; revisit `docker/deploy/tailscale` +
  sparkDash's `tailscaleMonitoring` unit flag once done.
- Replace the passphrase-less file key with a YubiKey-backed ssh-agent: reserved mount point and
  wiring are documented in `docker/deploy/sparkdash/README.md`.
