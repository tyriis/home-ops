<!-- markdownlint-disable MD046 -->

# Runbook: DNS resolution of local domains (`*.techtales.io`)

!!! abstract

    Containers on **bifrost** (LightWale OS) fail to resolve LAN-only names such as `ai.techtales.io`, while public domains resolve fine.
    Root cause: the host's static `/etc/resolv.conf` lists a Cloudflare **malware-filter** resolver (`1.1.1.2`) **before** the LAN resolver,
    and the filter answers local names with a hard negative - resolvers never fall through to the next server on a negative answer.

## Symptoms

Containers fail resolving `*.techtales.io` names. Typical new-api wording:

```text
No address associated with hostname
can not reach the dns server
```

- Public domains (`openai.com`) resolve fine — the DNS chain itself is healthy.
- The **host itself** fails the same way for local names (this is not container-specific).

## How DNS works on this host

```text
container /etc/resolv.conf -> 127.0.0.11 (Docker embedded DNS, in dockerd)
  dockerd forwards from the HOST network namespace to the host upstreams (ExtServers)
    1.1.1.2        Cloudflare malware filter   <- tried FIRST, answers NXDOMAIN for local names
    192.168.100.1  UniFi gateway (LAN records) <- consulted only on timeout/refusal, never on a negative answer
```

1. **Containers** get `nameserver 127.0.0.11` — Docker's embedded DNS, running inside `dockerd`.
2. **dockerd forwards from the host network namespace** to the host's upstreams. They are visible as the `ExtServers:` comment in a container's `/etc/resolv.conf` — **snapshotted at container creation**.
3. **The host** runs a static LightWale default `/etc/resolv.conf`:

   ```text
   nameserver 1.1.1.2
   nameserver 192.168.100.1
   ```

   - `192.168.100.1` = UniFi gateway — serves LAN records for `techtales.io` (written by the cluster's external-dns `unifi-records`).
   - `1.1.1.2` = Cloudflare **malware-filter** resolver — knows nothing about split-horizon internal zones.

## Diagnosis

| Command (context)                                    | Healthy / expected meaning                                                              |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `docker exec new-api cat /etc/resolv.conf`           | `nameserver 127.0.0.11` + `ExtServers:` comment = **normal** (Docker embedded DNS)      |
| `ip -4 addr show` (host)                             | Host is `192.168.100.10/24` - same subnet as the gateway; no cross-subnet issue         |
| `cat /etc/resolv.conf` (host)                        | Static LightWale default: `1.1.1.2` first, `192.168.100.1` second                       |
| `docker exec new-api getent hosts openai.com`        | Resolves = container -> dockerd -> host chain is healthy                                |
| `time nslookup ai.techtales.io 1.1.1.2` (host)       | **Fails fast** (instant NXDOMAIN-style negative, no timeout) - the discriminator        |
| `time nslookup ai.techtales.io 192.168.100.1` (host) | **Resolves** - the LAN resolver has the record all along                                |
| `docker exec new-api wget https://ai.techtales.io`   | Reproducing: `Resolving ai.techtales.io... failed: No address associated with hostname` |

The `time nslookup ... <server>` pair is the discriminator: **fails-fast against the filter vs resolves against the LAN resolver** proves it is resolver order, not connectivity.

## Root cause

The public first resolver (`1.1.1.2`) answers an authoritative-style **NXDOMAIN** for local-only names — _"No address associated with hostname"_, failing instantly with no timeout.

Resolvers do **not** fall through to the next server on a _negative answer_ — only on timeout/refusal — so the LAN resolver (`192.168.100.1`) that actually has the record is never consulted.

This is **not a Docker or LightWale bug**; it is resolver-order + split-horizon DNS.

## Fix (host-wide, preferred)

On bifrost via SSH:

### 1. Reorder the host resolvers

Edit `/etc/resolv.conf` — LAN first, plain Cloudflare as fallback:

```text
nameserver 192.168.100.1
nameserver 1.1.1.1
```

- `192.168.100.1`: LAN — serves `techtales.io`, forwards everything else.
- `1.1.1.1`: fallback — plain Cloudflare, **not** the `.2` malware-filter variant.

On LightWale this is a **static file** — the change persists across reboot.

### 2. Restart dockerd

There is no systemd on LightWale (busybox `S*NN` scripts):

```bash
sudo /etc/init.d/S60dockerd restart
```

If `restart` is unsupported by the script: `stop`, then `start`. Containers with `restart: unless-stopped` come back automatically.

### 3. Recreate the containers

Their `ExtServers` snapshot in `/etc/resolv.conf` is taken at creation, so containers must be recreated:

```bash
# in docker/bifrost/new-api on the host
docker compose up -d --force-recreate
```

Or simply let doco-cd redeploy.

## Alternative fix (per-container, no host change)

Add to the service in `docker/deploy/new-api/compose.yaml`:

```yaml
dns: ["192.168.100.1", "1.1.1.1"]
```

GitOps-managed and survives host reinstalls, but only fixes **that container** — host-level lookups stay broken.

## Verification

```bash
# LAN IPs returned instead of the negative answer
docker exec new-api getent hosts ai.techtales.io

# end-to-end through the gateway
docker exec new-api wget -qO- --timeout=10 https://ai.techtales.io
```

## Caveats

!!! warning

    **Docker snapshots `ExtServers` at container _creation_.** Restarting the Docker daemon alone leaves existing containers
    pointing at the stale resolvers - they must be recreated.

!!! warning

    **Watch for IPv6-only answers.** Proxied Cloudflare names can return AAAA-only records whose v6 address decodes to public
    Cloudflare space; Docker bridge networks have no IPv6 route. Check `docker exec new-api getent ahostsv4 <name>` and confirm
    with an end-to-end `wget` - do not trust `getent` success alone.

!!! warning

    For LAN-only use, an alternative is a **UniFi DNS override** pointing the hostname at its LAN IP, so containers
    short-circuit Cloudflare entirely.

!!! warning

    **Never use `1.1.1.2` / `1.1.1.3` as a primary resolver** on a network with split-horizon zones - they answer local
    names with hard negatives that suppress fallback.
