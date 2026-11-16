# bifrostix Phase B — btrfs impermanence with named-subvolume root

Issue: [#11792](https://github.com/tyriis/home-ops/issues/11792)
Parent spec: `2026-11-07-nixos-hardened-docker-lane-design.md` (reference shape,
item 2: "Ephemeral root, declared persistence only")

## Intent

Make bifrostix's root filesystem recreated from a known-good snapshot on every
boot. Everything that survives a reboot must be declared. Config drift stops
being a discipline ("anything hand-written on a NixOS system is a lie") and
becomes structural: hand-written state cannot survive.

This also closes the fleet-consistency gap: root moves from the unnamed btrfs
top-level to a named `@` subvolume, matching the fleet's named-subvolume
convention.

## Facts this spec bakes in (verified 2026-11-16, live + at pin d5cc6833)

- Host: bifrostix, NixOS 26.11.20261113.d5cc683, kernel 6.18 pinned,
  reserved address 192.168.30.31 (controller-owned DHCP, #11969).
- Disk: `nvme0n1p2` btrfs, UUID 4e2aa3de-4b26-4a84-bde5-13465a488466,
  label `root`. Mounted at `/` as `subvolid=5,subvol=/` — the top-level
  FS_TREE is the root. Default subvolume: 5 (FS_TREE).
- Existing named subvolumes: `home`, `nix`, `srv`, `tmp`, `var/tmp`,
  `var/lib/portables`, `var/lib/machines`. `/nix` is already a separate
  subvolume mount.
- No `@`, no snapshots, no swap on disk (zram only).
- The nixpkgs pin has **no** upstream impermanence module. Verified: no
  `persistent-data` module exists at d5cc6833. Third-party
  nixos-impermanence is rejected: a new flake input for ~50 lines of
  unit logic we must own anyway.

## Design

### Subvolume layout

Create beside the running system (non-destructive), then flip:

| Subvolume                             | Mount point             | Lifetime                                                        |
| ------------------------------------- | ----------------------- | --------------------------------------------------------------- |
| `@`                                   | `/`                     | deleted and re-snapshotted from `@base` every boot              |
| `@base`                               | (not mounted)           | pristine seed of `@`; re-seeded only after a proven-good boot   |
| `@persistent`                         | `/persistent`           | persistent; the only allow-list root                            |
| `@docker`                             | `/persistent/docker`    | persistent; becomes Docker `data-root`                          |
| `home`                                | `/home`                 | unchanged                                                       |
| `nix`                                 | `/nix`                  | unchanged; the store must not roll back — generations are state |
| `tmp`, `var/tmp`                      | (deleted)               | replaced by tmpfs `/tmp` and `/var/tmp`                         |
| `srv`, `var/lib/{portables,machines}` | (deleted, cleanup pass) | unused                                                          |

`/boot` (vfat, p1) is unchanged and stays writable-boot.

### Mechanism — owned module `nixos/modules/impermanence-btrfs.nix`

One module, reused by every future NixOS host. Per-device configuration:
fs device, root subvolume name, base subvolume name, persist subvolume,
bind list.

- **Boot (`boot.initrd.postDeviceCommands`):** mount the filesystem top-level
  read-write; `btrfs subvolume delete @`; `btrfs subvolume snapshot @base @`;
  unmount; normal mount continues onto the fresh `@`. The wipe is two
  commands; there is no rsync and no tmpfs copy.
- **Persistence binds:** plain declarative `.mount` units
  (`options = [ "bind" ]`, `device = /persistent/<path>` →
  the live path) generated per allow-list entry. Ordering against the
  rendered `.mount` unit names.
- **Re-seed (`impermanence-reseed.service`, oneshot, manual start):**
  delete `@base`, snapshot live `@` → `@base`. "Good state" is defined only
  by an explicit operator action. See decision.

### Persist allow-list (everything lives under `/persistent`, bind-mounted)

- `/etc/ssh` — host keys. Stable identity across reboots and address moves.
- `/var/lib/nixos` — uid/gid identity database. Without it, users and
  service accounts renumber every boot (the classic failure of naive
  impermanence).
- The sealed journald state and log directories — Phase A2 seal requires
  persistent state; a lost seal breaks boot-time verification.
- `/etc/machine-id` — identity used by journald-seal and friends.
- `/root/nixos` — the config tree (until the host moves to a real git
  checkout of this repo — a tracked follow-up).
- `/persistent` itself.
- `/persistent/docker` (via `@docker`) — declared `data-root` for Docker.
  The lane lands on top of this; a runaway container can fill only its own
  subvolume.

Anything else on `/` has a guaranteed lifetime of one reboot. That is the
feature.

### Reseed decision

**Chosen: manual.** `systemctl start impermanence-reseed` after each change
that booted, ran, and was accepted. An automatic timer (survive-N-minutes
promotion) was rejected: a config that fails at minute six gets promoted by
minute five-plus-five. Operator ceremony is the cost; "the base is only ever
a state I approved" is the gain. The reseed unit is expected to be started
in the same session that ran the switch.

### Escape lanes (ordered by cost)

1. **PR-A first, before any layout change:** initrd SSH
   (`boot.initrd.network.ssh`, port 2222, this host's root key), proven by a
   deliberate reboot drill. This is the out-of-band path if a boot ever
   fails before root mounts: log in, inspect, repair with `btrfs`, or
   `set-default` an older entry. Phase C (LUKS2+TPM2) inherits this lane as
   its unlock path.
2. **Old generations stay bootable as-is.** Migration never deletes or
   moves the top-level tree (`subvolid=5` / `subvol=/` keeps existing with
   its old contents untouched while new subvolumes are created beside it).
   Old systemd-boot entries carry the old kernel cmdline (`subvol=/`), so
   they boot the pre-Phase-B tree. Rollback = pick an old entry.
3. Physical console (present for the migration boot).

### Migration sequence (one host, one window, deliberate)

1. PR-A: initrd SSH. Switch, reboot, **prove** the 2222 shell. No layout
   work merges before this drill passes.
2. Create subvolumes beside the live system: `@`, `@persistent`,
   `@docker`. Seed content: rsync `/` → `/mnt/@` (exclude `/nix`, `/home`,
   `/boot`, `/proc`, `/sys`, `/dev`, `/run`, `/tmp*`, `/var/tmp`, current
   `/var/lib/docker`), copy allow-list paths into `@persistent`.
   Docker has no containers yet — the lane was deliberately deferred
   behind this phase, so no runtime data moves.
3. Snapshot `@` → `@base`.
4. PR-B: hardware config flips to the new layout — `fileSystems./` gains
   `options = [ "subvol=@" ]`; add `/persistent`, `/persistent/docker`
   (subvol options), tmpfs `/tmp` and `/var/tmp`; import
   `impermanence-btrfs.nix`; set Docker `data-root` to
   `/persistent/docker`. Gate: eval + `--dry-run` build at the pin.
5. Switch. Activation applies the new mounts that can live-apply; `/`
   changes only at boot.
6. **Boot gate (irreversible-by-choice, reversible-by-lane):** reboot,
   verify `findmnt /` shows `subvol=@`, `/persistent` populated, 0 failed
   units, sshd/docker/networkd/nftables active, sealed journal functional
   (`journalctl --verify`).
7. Verify, commit nothing further, start the reseed — the base now equals
   the approved state.
8. Cleanup pass (later PR): delete `tmp`, `var/tmp`,
   `var/lib/{portables,machines}`, `srv` subvolumes; drop the old
   top-level tree once Phase C no longer needs the old-generation
   rollback lane.
9. Second reboot: prove the wipe actually works — `touch
/root/ephemeral` before, confirm it is gone after, and confirm
   `/root/nixos`, host keys, machine-id, journal survive.

### Non-goals for this spec

- LUKS2 + TPM2 enrollment (Phase C, next: initrd SSH unlock +
  `systemd-cryptenroll` on this layout).
- `@snapshots` history / snapper-style roll-forward. Single base +
  generation-rollback covers the need; history can land later beside it.
- Host git-checkout (config source) — separate follow-up.
- `/home` treatment — the pilot runs no interactive users beyond root;
  revisit with the lane.

## How to verify

- After PR-A: an initrd shell on port 2222, reachable while `/` is not yet
  mounted (proven during the drill reboot).
- After step 6: `findmnt /` reports `subvol=@`; `findmnt /persistent`
  reports `subvol=@persistent`; `findmnt /persistent/docker` reports
  `subvol=@docker`.
- After step 9: the ephemeral marker is gone; every allow-list path is
  present; `journalctl --verify` reports no Bad/Corrupted entries.
- Reboot count to close Phase B: three planned (drill, flip, wipe-proof),
  each self-recovering by design.
