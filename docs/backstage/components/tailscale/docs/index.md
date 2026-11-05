# tailscale

## overview

Tailscale provides the WireGuard mesh that connects the Docker hosts outside Kubernetes — the TrueNAS
NAS, the Synology DS218+ and, historically, bifrost. It carries two jobs beyond plain node membership:

- **Subnet router** — advertises the LAN subnets so offsite tailnet clients reach them without a
  Kubernetes ingress in the path.
- **Exit node** — routes a client's whole internet egress through the NAS.

Both roles used to belong to the TrueNAS SCALE tailscale middleware app. That app is retired; the
role now belongs to the doco-cd stack in `docker/truenas/tailscale/`
([#8227](https://github.com/tyriis/home-ops/issues/8227)).

## deployment

One shared definition, one stack per host — the same include-shim pattern as the other doco-cd
services:

- Shared compose: `docker/deploy/tailscale/compose.yaml`
- Host shims: `docker/<host>/tailscale/compose.yaml`, each `include:`ing the shared file with
  `project_directory: .` so relative paths resolve in the host directory
- Registration: `docker/.doco-cd.<host>.yaml` (`name: tailscale`, `working_dir`, `env_files: [.env]`)
- Image: `ghcr.io/tailscale/tailscale:v1.104.4`, digest-pinned; Renovate bumps it through `docker/`

| Host                         | Host directory               | State                                 | Role                                                                      |
| ---------------------------- | ---------------------------- | ------------------------------------- | ------------------------------------------------------------------------- |
| `nas.techtales.io` (TrueNAS) | `docker/truenas/tailscale/`  | named volume `tailscale_data`         | exit node, routes `192.168.100.0/24`, `192.168.1.0/24`, `192.168.30.0/24` |
| `synology`                   | `docker/synology/tailscale/` | bind `/volume1/docker/tailscale/data` | exit node, route `192.168.200.0/24`                                       |
| `bifrost`                    | `docker/bifrost/tailscale/`  | named volume `tailscale_data`         | dormant — not deployed, see below                                         |

Container shape, per the shared file: `network_mode: host`, `/dev/net/tun`, `privileged: false`,
`cap_drop: [ALL]` plus `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `NET_ADMIN`, `NET_RAW`, `SYS_MODULE`,
`no-new-privileges`, a `tmpfs` for `/var/run/tailscale`, and a `tailscale status` healthcheck. The
kernel-mode tun device is what the app also used; userspace mode (`TS_USERSPACE=true`) is not in play.

### configuration

`.env` holds only plain, per-host values (`TARGET`, and a state path where one is bound). Everything
else lives in `sops.env`, age-encrypted to that host's recipient — the rule
`docker/<host>/*/sops.env` in `.sops.yaml` selects it:

| Key             | Value                                                        | Why                                                                                 |
| --------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `TS_AUTHKEY`    | single-use, non-ephemeral key                                | registration only; never consumed once state exists                                 |
| `TS_AUTH_ONCE`  | `true`                                                       | do not re-auth or overwrite prefs on restart                                        |
| `TS_ACCEPT_DNS` | `true`                                                       | MagicDNS plus the split-DNS routes for `techtales.io` and friends                   |
| `TS_USERSPACE`  | `false`                                                      | kernel mode over `/dev/net/tun`                                                     |
| `TS_EXTRA_ARGS` | `--advertise-exit-node --accept-routes --advertise-routes=…` | gateway role; `--accept-routes` makes the LAN subnets reachable from the NAS itself |

The shared compose loads `env_file: ${SOPS_ENV_FILE:-sops.env}` only, so a value placed in `.env`
never reaches the container — routing flags and the authkey must stay in `sops.env`.

## routing caveats

- Advertising an exit node makes tailscale disable SNAT for the advertised subnet routes, so return
  traffic depends on tailscaled's policy routing rather than NAT.
- tailscaled then tries a connmark `rp_filter` workaround by writing
  `net.ipv4.conf.all.src_valid_mark`, which fails in a container (`/proc/sys` is read-only) and logs
  `router: warning: failed to enable src_valid_mark`. This is harmless here: both NAS hosts run
  `net.ipv4.conf.all.rp_filter = 0`, so reverse-path filtering never drops the return traffic the
  workaround guards against. The middleware app ran under identical conditions.
- `ip6tables` is unavailable in the container (`modprobe` finds no `/lib/modules`), so netfilter is
  IPv4-only. Every advertised route is IPv4.
- **One daemon per host.** Two tailscaled instances sharing one state directory — and therefore one
  node key — make the tailnet flap between them. Stop the previous container before starting a new one.

## state and identity

Node identity is `tailscaled.state` in `TS_STATE_DIR`. Keeping it keeps the `100.x` address, the device
name, and the approved routes and exit-node flag; losing it costs a fresh registration plus manual
approval in the tailnet admin console.

Moving a node to a new stack — this is how the TrueNAS app was replaced without re-registering:

```sh
docker volume create tailscale_data
docker run --rm \
  -v tailscale_data:/dst \
  -v /mnt/.ix-apps/app_mounts/tailscale/state:/src:ro \
  alpine sh -c 'cp -a /src/. /dst/ && ls -l /dst'
```

`tailscaled.state` in the listing is the proof. The source is only read, so the old stack still starts
with the same identity while it remains installed — as a fallback that has to stay stopped whenever the
new stack runs.

## adding a host

1. `docker/<host>/tailscale/` with a shim copied from an existing host, plus `.env` carrying `TARGET=<host>`.
2. `sops.env` encrypted to that host's age recipient; add a `docker/<host>/*/sops.env` rule to `.sops.yaml` if the host has none yet.
3. Entry in `docker/.doco-cd.<host>.yaml`: `name: tailscale`, `working_dir`, `env_files: [.env]`.
4. Deploy, then approve any advertised routes and the exit-node flag for the new device; set `TS_EXTRA_ARGS` to match what that host should advertise.

Hosts with a Docker-managed state volume need no preparation; hosts binding a host path must have the
path present, since the shim sets `create_host_path: false`.

## bifrost (dormant)

The bifrost stack exists but is not registered in `docker/.doco-cd.bifrost.yaml`. Lightwhale cannot
provide a boot-reliable subnet router: persistent `/etc` becomes visible only at `S11persistence`
inside a forward-only `rcS`, the netfilter kernel is cut-down, and a clean reboot hung and needed a
hard reset. Runtime behaviour — registration, peering, subnet routing, offsite transit — was validated
before that.

To re-adopt it on another host: register the host in its doco-cd config with a host-init hook that runs
early and persists, mint a fresh authkey, and re-encrypt that host's `sops.env`.

## verification

From a client off the LAN:

```sh
tailscale ping truenas
ping -c2 <host in each advertised subnet>
tailscale up --exit-node=truenas && curl -s ifconfig.me   # expect the WAN address
tailscale up --exit-node=
```

On a host, `docker logs tailscale` should show `machineAuthorized=true` and no re-registration, and
`docker exec tailscale tailscale status` should list the node at its previous `100.x` address.
