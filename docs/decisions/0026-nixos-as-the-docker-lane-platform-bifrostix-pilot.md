---
status: accepted
date: 2026-11-15
decision-makers: [tyriis]
---

# NixOS as the docker-lane platform — bifrostix pilot

## Context and Problem Statement

The docker-lane hosts (bifrost, truenas) run appliance OSes. `bifrost` runs
Lightwhale OS with BusyBox init, no systemd, and host-level state (TUN module,
sysctls) kept alive by `/etc/init.d/SNN` scripts that have repeatedly failed at
boot without a trace. Host configuration on those machines is hand-written and
invisible to this repository. We want a minimal, hardened compose host where
the OS itself is reviewable, reproducible, and rollback-able from git.

Research during the pilot (2026-11-15) corrected a premise worth recording:
Lightwhale is not a closed vendor product — it is a public single-maintainer
project (Denmark, one author). Its _structure_ is good and worth keeping:
read-only root, disposable OS media, all state segregated on a data
filesystem. Its _process_ is exactly what a single-maintainer project
struggles to provide: a 23-month gap with zero published updates, updates
requiring a manual `dd` of a new ISO, no OS rollback, shipped default
credentials. The target for the NixOS lane was set accordingly: keep the
structure, industrialize the process — signed, pinned, automated updates and
generation-based rollback.

## Considered Options

- **Stay on Lightwhale / appliance OS.** Rejected: host config stays
  imperative, boot reliability problems recur with no bisectable history, and
  the update-pipeline gap above is structural to how the OS is built.
- **Fedora CoreOS / openSUSE MicroOS.** Rejected in the spec discussion
  (#11792): their immutable layers fight a plain Docker + compose fleet —
  rpm-ostree layering works against the immutability model on CoreOS.
- **Talos / Bottlerocket.** Rejected for this lane: they are Kubernetes-only
  by design. Talos remains the right answer for the _orchestrated_ lanes
  (main/utility); the docker-lane deliberately stays compose-based via
  doco-cd and Arcane.
- **NixOS (chosen).** Docker, firewall, sysctls, sshd policy, and (later) the
  impermanence persist-whitelist are all first-class module options in the
  same flake that already owns the truenas migration. Generations give
  rollback natively; a pin gives reproducibility; there is no package manager
  drift at runtime. NixOS is a new discipline for the fleet, so the pilot
  shape (one spare NUC, one lane) was scoped to de-risk it.

## Decision Outcome

Chosen: **NixOS 26.05 (unstable) as the docker-lane platform**, piloted on a
NUC7i5 (`bifrostix`, 16 GB RAM, 238 GB NVMe). Concretely:

- **Flake tree in this repo** at `nixos/` (PR #11927): pinned nixpkgs input,
  a reusable `modules/docker-lane.nix` baseline, thin per-host profiles, and
  the generated hardware config beside them. Host rebuilds run
  `nixos-rebuild switch --flake` from that tree. Anything hand-written on a
  NixOS host is a lie — the bootstrap `/etc/nixos` era is measured in hours.
- **Kernel is LTS and pinned**: `boot.kernelPackages = pkgs.linuxPackages_6_18`.
  A headless node needs security fixes, not bleeding-edge features, and a
  pinned name prevents a channel update from silently swapping the kernel.
- **Filesystem btrfs, swap is zram only** (16 GB host — disk swap converts an
  OOM verdict into thrashing; a swapfile on btrfs is the COW-cursed path).
  **systemd-networkd, not NetworkManager**; sshd key-only. Docker on
  overlay2 with daemon-default `json-file` logs, 10m x 3 — the fleet pattern
  from #11541, now enforced by the OS instead of by per-host convention.
- **Hardening phase A shipped 2026-11-15** (`modules/hardening.nix`, verified
  research-backed baseline): sshd completion policy (`AuthenticationMethods
publickey`, throttling, alive-reaping — crypto left at OpenSSH defaults,
  which are post-quantum hybrid and better than any hand-picked list);
  nftables default-deny input as a self-owned ruleset with the full ICMPv6
  NDP set kept (blanket-dropping it silently breaks IPv6) and forward
  intentionally open while Docker owns it; the CIS-L1/kspp sysctl set, kept
  Docker-compatible (loose `rp_filter`, no `modules_disabled`, no
  `hung_task_panic`, no userns kill); `softlockup_panic=1` + `panic=30` — on
  an unattended box, panic is recovery.
- **Deliberate non-controls**, with reasons: default-deny egress (container
  egress is masqueraded to the host IP; host-nftables can't distinguish
  workloads — log-rate-limit instead), rootless Docker and `userns-remap`
  (real containment, but operationally wrong for this fleet until a cutover
  with no legacy images), forced kernel lockdown (no Secure Boot on this
  hardware), brute-force bans (log hygiene, not a security boundary —
  key-only auth is the control).
- **Phases B–D remain planned** (tracked #11792): B impermanence with a
  persist-whitelist and the `@` subvol fix — before workloads land; C LUKS2 +
  TPM2 convenience sealing, gated on a proven initrd-SSH unlock path;
  D update automation (flake-based rebuild cadence) — the specific gap
  Lightwhale's process could not close.

## Consequences

- Positive: the host's full security posture is now a reviewed diff in this
  repo; a bad change is a boot-entry away from gone; the pilot proves the
  module shape truenas will reuse.
- Accepted costs: NixOS expertise is new for the fleet; unstable channel
  requires deliberate bumps; host root subvol is still `/` and the UniFi
  lease is not yet pinned — both must close before stacks migrate.
- Operational rules learned during the pilot and encoded in module comments:
  an nftables service restart mid-run flushes Docker's iptables-nft tables —
  restart docker right after; cold boot has no such race. Never bundle two
  brick-risk controls in one rebuild; arm a dead-man rollback timer before
  any firewall change and verify fresh SSH sessions before disarming.
