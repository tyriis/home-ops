# System: bifrostix

`bifrostix` is a NUC7i5 running **NixOS as the docker-lane pilot host** — the
planned replacement for [bifrost](https://github.com/tyriis/home-ops/blob/main/docs/backstage/systems/bifrost/docs/index.md). Full decision
record and option analysis: **[ADR 0026 — NixOS as the docker-lane
platform](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0026-nixos-as-the-docker-lane-platform-bifrostix-pilot.md)**.
Pilot issue #11792, flake PR #11927, spec
`docs/superpowers/specs/2026-11-07-nixos-hardened-docker-lane-design.md`.

Everything about this host is a reviewed diff in this repository: the
`nixos/` flake tree holds the nixpkgs pin, the reusable docker-lane baseline
(`modules/docker-lane.nix`), the hardening baseline (`modules/hardening.nix`),
the thin host profile, and the generated hardware config. Rebuilds run on
target from that tree: `nixos-rebuild switch --flake .#bifrostix`.

## Current state

| Item          | Value                                                            |
| ------------- | ---------------------------------------------------------------- |
| Hardware      | Intel NUC7i5 (i5-7260U, Kaby Lake), 16 GB RAM, 238 GB NVMe       |
| OS            | NixOS 26.05 (unstable), flake-built from `nixos/` in this repo   |
| nixpkgs pin   | `f1e5c356f35d07e7b71a6b5e6c9338e0b029e0c0` (flake.lock)          |
| Kernel        | 6.18.x LTS, pinned via `boot.kernelPackages`                     |
| Boot          | systemd-boot, EFI, btrfs root (subvol `/` — see gaps)            |
| Swap          | zram only (no disk swap, no swapfile)                            |
| Network       | systemd-networkd, DHCP at 192.168.30.232 (fixed lease pending)   |
| Host services | sshd (key-only + policy), dockerd, timesyncd — nothing else      |
| Docker        | overlay2 on btrfs, daemon-default json-file 10m x 3              |
| Firewall      | nftables `inet filter`, input default-deny, SSH throttled 30/min |
| Hardening     | Phase A of the ADR — applied 2026-11-15, gen 8                   |

## Verify live state

Re-check rather than trusting this page. All probes run over SSH as root.

| Check             | Probe                                                            | Expect                                     |
| ----------------- | ---------------------------------------------------------------- | ------------------------------------------ |
| Firewall live     | Run `nft list ruleset` and count `policy drop` occurrences       | 1 — input only; forward/output stay accept |
| Core services     | `systemctl is-active nftables sshd docker`                       | `active` x3                                |
| Sysctls persisted | `sysctl -n kernel.yama.ptrace_scope kernel.softlockup_panic`     | `1` and `1`                                |
| Docker contract   | `docker info --format '{{.Driver}} {{.LoggingDriver}}'`          | `overlay2 json-file`                       |
| Declarative no-op | Run `cd /root/nixos && nixos-rebuild switch --flake .#bifrostix` | `Done.` with no diff                       |

## Known gaps

| Gap                         | Gate                                                                |
| --------------------------- | ------------------------------------------------------------------- |
| Root subvol is `/`, not `@` | Repartition in phase B (impermanence) — before stacks land          |
| No fixed UniFi lease        | Pin DHCP + DNS record; host has churned once at the networkd switch |
| No update automation yet    | Phase D — rebuild cadence over the pinned flake                     |
| No LUKS/TPM, no initrd SSH  | Phase C — unlock path must be proven before sealing                 |

## Operational notes

- **One risky control per rebuild**, reboot-gated; every rebuild so far has
  self-recovered after a clean reboot (4 gates, ~80 s to back).
- Firewall changes carry a **dead-man rollback timer**
  (`systemd-run --on-active=180s <previous-generation>/bin/switch-to-configuration switch`),
  disarmed only after fresh SSH sessions are proven. Note `systemctl abort`
  leaves a transient timer pending — stop it explicitly.
- **An nftables service restart mid-run flushes Docker's iptables-nft
  tables.** Restart docker right after to re-sync published ports. Cold boot
  has no such race (dockerd starts after nftables).
