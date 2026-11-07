# NixOS hardened docker-lane host pattern (pilot for bifrost retirement)

Issue: [#11792](https://github.com/tyriis/home-ops/issues/11792)

## Intent

Define a minimal, secured, immutable host pattern for the docker lane — plain
Docker hosts whose containers are managed by doco-cd and Arcane — and stand it up
on a spare device as a parallel test instance. Nothing production is touched:
bifrost stays as-is until the pattern is proven on the pilot. The pilot's output
is a reusable NixOS baseline module that a future bifrost (and any later bare
host) adopts as a thin per-host profile.

## Background

bifrost runs the Lightwhale vendor OS: a read-only squashfs root, a BusyBox init
with an `S01..SNN` script chain that is not boot-reliable (no `/etc/rc.d`; the
tailscale boot attempt in #11420 died here, and one recovery needed a hard
reset), a cut-down netfilter kernel, and a daemon-wide `--log-driver=syslog`
quirk. It also runs 1panel, which logs failed admin logins from the internet.
The decision to retire the vendor OS is taken; this spec takes the lane and the
shape.

## Lane decision (taken, rationale recorded)

Two options were weighed for what replaces Lightwhale:

- **Talos worker in utility.** Pros: one OS discipline for servers, patching via
  the known Talos flow. Cons: a second *worker* into a single-control-plane
  cluster adds capacity but zero redundancy; every app inherits util01's failure
  domain and apply-config churn; and it forces the docker-lane apps (new-api,
  Arcane, host-level Traefik) into a k8s rewrite for no isolation gain.
- **Standalone docker-lane host, NixOS — chosen.** Keeps inference / AI-edge
  workloads deliberately out of the clusters: fat single-process RAM profiles
  that schedule badly on a small shared cluster, host networking and device
  needs, and blast-radius separation — utility hosts the fleet's own
  observability (vmsingle, VictoriaLogs), so a runaway inference container there
  takes monitoring down with it.

NixOS is chosen over other immutable candidates because the truenas migration
adopts it regardless (kernel host services — ZFS, knfsd, Samba — are exactly
what Talos cannot host), so the onboarding cost is paid once, not per host.
Screening at time of writing: Fedora CoreOS is the strongest alternative but
Docker arrives only via `rpm-ostree` layering, which fights the immutability
model at every major; openSUSE MicroOS keeps docker in-tree but has a weaker
declarative-config story; Flatcar is losing momentum (AKS deprecation,
community-only upkeep); Bottlerocket and Talos have no compose lane. Only NixOS
puts Docker, firewall, sysctls, and the persist whitelist in the same
declarative module as everything else.

## Reference shape of the hardened compose host

1. **Boot integrity.** UEFI + UKI + Secure Boot, LUKS2 sealed to TPM2
   (`systemd-cryptenroll`, PCR-bound). Where firmware allows.
2. **Ephemeral root, declared persistence only.** Root is tmpfs, rebuilt from
   the current generation every boot. Survivors are exactly the whitelist below;
   drift is structurally impossible, not lint-detected.
3. **Host service surface = `sshd` + `dockerd` + time sync. Nothing else.**
   `dockerd` is the platform, not an app: everything else — doco-cd,
   arcane-agent, Traefik, the vmagent/vl-collector trio, every workload — is a
   container, so it is already inside the existing GitOps and observability
   pipelines. No vendor panels, no admin UIs, no cockpit/avahi.
4. **Default-deny twice.** nftables drops inbound except 22 from the management
   net (+ tailscale later, if re-added); the fleet loopback discipline holds —
   scrapables bind `127.0.0.1`, only the host Traefik publishes. Docker injects
   its own nftables chains for published/forwarded ports that bypass the input
   policy, so the forward-chain posture is a declared decision, and a central
   audit of `docker ps` published ports against intent is part of the pattern.
5. **Kernel hardening, tuned for a container host.** CIS-style sysctls
   (`kptr_restrict`, `dmesg_restrict`, `ptrace_scope=1`, syncookies, rp_filter,
   link-protection); blacklist only the exploit-historic protocol modules
   (dccp/sctp/rds/tipc). Explicit non-goal: `modules_disabled` and blanket
   `fs-*` / `net-pf-*` / `crypto-*` refusal are forbidden on a Docker host —
   Docker loads netfilter/nf_conntrack/bridge and fs types on demand; a hardened
   host that breaks its runtime eventually gets the hardening switched off.
6. **Two independent atomic update lanes, no overlap.** OS: a new generation
   (or a full re-provision from the flake) with rollback. Containers: untouched
   by the OS lane; images stay pinned under doco-cd/Arcane.
7. **Cattle, provably.** The whole host is one module in the home-ops flake:
   baseline module + per-host profile carrying only disk layout and role.
   Secrets stay sops-encrypted in git.

### Docker daemon, declarative

`virtualisation.docker.enable` with daemon settings owned by the module:

- `log-driver: json-file` with the canonical bounded rotation block (#11541:
  max-size 10m, max-file 3, VictoriaLogs attrs) set as the **daemon default**,
  so unmanaged strays are covered too — the bifrost syslog quirk dies at the
  source.
- explicit `data-root` on a dedicated filesystem/mount, so a runaway container
  can never fill `/` or the persist device.
- socket discipline: `/var/run/docker.sock` stays `root:docker` 660; the docker
  group is system-only — the socket is mounted into the doco-cd and
  arcane-agent containers, no human user is a member. Operators probe with
  sudo.

### Bootstrap chain and persist whitelist

The three daemons boot from image state only. Persisted paths, and only these:

| Path                          | Why                                                    |
| ----------------------------- | ------------------------------------------------------ |
| `/etc/ssh/`                   | host keys; `authorized_keys` from the module, not here |
| `/etc/machine-id`             | identity stability (metrics `host=`, log `hostname=`)  |
| Docker `data-root` mount      | images, volumes — container state                      |
| `/etc/doco-cd/`               | the host age key — the only bootstrap secret           |

Boot sequence: sshd + dockerd up → one-time manual `docker compose up` of the
doco-cd stack (same bootstrap procedure as every current docker-lane host) →
git owns the host from then on. A wipe + reflash + these four paths returns any
host to fleet-green; that property *is* the test.

## Test pilot: the spare device

- Hostname decision (owner): proposed **`frost`** — sibling naming to bifrost,
  signals "pilot for the bifrost replacement". Metrics `host=frost`, log stream
  `hostname=frost`, no `cluster` label (per the #11470 off-cluster convention).
- LAN-only addressing, management-net-restricted ssh; no Cloudflare, no public
  DNS.
- Wired exactly per the shape above. Per-host profile adds nothing beyond disk
  layout and the pilot role.
- Stacks on the pilot, minimal but representative: doco-cd, arcane-agent,
  node-exporter/vmagent trio, victoria-logs-collector, Traefik only once
  publishing/forwarding is exercised.
- Registration follows the established onboarding: `.doco-cd.frost.yaml`, sops
  rules + age key, vmauth user `frost-metrics` on utility, vl-collector with
  the containers-glob pointed at the exact data-root.

## Acceptance criteria

1. Reproducibility: host wiped, reflashed from the flake image, re-bootstrapped,
   and returns fleet-green from git alone.
2. Reboot drill: after a deliberate reboot (the failure mode that killed
   tailscale on Lightwhale), everything returns with zero manual steps —
   modules, sysctls, whitelist mounts, dockerd, all containers.
3. Hardening verify-suite green (sysctls, effective sshd config, nftables
   ruleset, docker group membership, published-port audit) and shipped as
   declarative assertions, reported centrally.
4. Pipeline green: `up{host="frost"}` series live via vmagent/vmauth; json-file
   container logs visible centrally with compose attrs; host-level syslog/journal
   shipping as designed.
5. Update drill: OS generation bump with verified rollback; container lane
   untouched by it.
6. Impermanence proof: an undeclared file written to `/etc` and `$HOME` is gone
   after reboot; every whitelisted path survives.

## Risks and open questions

- **Persist-list correctness** is the classic impermanence failure mode; the
  pilot's reboot drill exists specifically to catch it.
- **Secure Boot / TPM2 sealing** depends on the pilot device's firmware; if
  weak, the pilot records the degraded boot story rather than blocking.
- **Docker's forward-chain rules** bypass input policy — needs an explicit
  nftables integration decision (not `firewall-backend: iptables` legacy) before
  the pattern ships.
- **Hardware inventory of the spare device** (CPU/RAM/NIC/UEFI) is a prerequisite
  for the first profile commit.
- bifrost adoption, 1panel/data retirement plan, and the tailscale re-add are
  explicitly out of scope until the pilot passes; follow-up issues then.
