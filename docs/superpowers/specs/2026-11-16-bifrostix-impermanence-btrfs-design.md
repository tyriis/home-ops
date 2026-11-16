# bifrostix Phase B — btrfs impermanence with named-subvolume root

Issue: [#11792](https://github.com/tyriis/home-ops/issues/11792)
Parent spec: `2026-11-07-nixos-hardened-docker-lane-design.md` (reference shape,
item 2: "Ephemeral root, declared persistence only")

Revision 2 (2026-11-16): folded in the oracle review of rev 1. Headline
changes — the wipe mechanism is ported to systemd stage-1 (the scripted-initrd
options do not exist at our pin), the wipe/reseed sequences become guarded and
atomic, failure handling is decided explicitly as **fail-open with a loud
marker** (see Decisions), the escape-lane and initrd-SSH assumptions are
corrected, and a deliberate break-and-restore drill joins the migration
sequence.

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
- **Scripted stage-1 is gone at the pin.** `boot.initrd.postDeviceCommands`
  and `boot.initrd.extraUtilsCommands` are `mkRemovedOptionModule`
  (hard eval error); `boot.initrd.systemd.enable` is gone because
  systemd stage-1 is the only stage-1
  (`nixos/modules/system/boot/systemd/initrd.nix`). All initrd-side
  mechanism below is `boot.initrd.systemd.*`.
- NIC is `e1000e`, and it is currently **absent** from
  `hardware-bifrostix.nix` initrd modules. Initrd SSH (PR-A) requires it.
- Old systemd-boot entries carry **no** `subvol=` option: they boot FS_TREE
  because it is the *default* subvolume, not by explicit choice. This makes
  the rollback lane destroyable by a single `set-default` — see Escape lanes.

## Design

### Subvolume layout

Create beside the running system (non-destructive), then flip:

| Subvolume                             | Mount point             | Lifetime                                                        |
| ------------------------------------- | ----------------------- | --------------------------------------------------------------- |
| `@`                                   | `/`                     | deleted and re-snapshotted from `@base` every boot              |
| `@base`                               | (not mounted)           | read-only pristine seed of `@`; re-seeded only after a proven-good boot |
| `@persistent`                         | `/persistent`           | persistent; the only allow-list root                            |
| `@docker`                             | `/persistent/docker`    | persistent; becomes Docker `data-root`                          |
| `@journal`                            | `/var/log/journal`      | persistent; journald state and sealed journals (own subvolume — see Persistence) |
| `home`                                | `/home`                 | unchanged                                                       |
| `nix`                                 | `/nix`                  | unchanged; the store must not roll back — generations are state |
| `tmp`, `var/tmp`                      | (deleted)               | replaced by `boot.tmp.useTmpfs` + zram (already the shape)      |
| `srv`, `var/lib/{portables,machines}` | (deleted, cleanup pass) | unused                                                          |

`/boot` (vfat, p1) is unchanged and stays writable-boot.

All subvolumes live directly under FS_TREE. The filesystem is one shared
pool: subvolume isolation is a **lifetime** boundary, not a capacity
boundary — a runaway container can consume the whole filesystem unless
qgroups are enabled later. Not a Phase B goal; stated so nobody re-learns it.

### Mechanism — owned module `nixos/modules/impermanence-btrfs.nix`

One module, reused by every future NixOS host. Per-device configuration:
fs device, root subvolume name, base subvolume name, persist subvolume,
bind list.

**Wipe (`boot.initrd.systemd.services."impermanence-wipe"`)** — a
`Type=oneshot` service with:

- `unitConfig.DefaultDependencies = false`
- `after = [ "initrd-root-device.target" ]`
- `before = [ "sysroot.mount" ]`
- `requiredBy = [ "initrd-root-fs.target" ]`
- `serviceConfig.TimeoutStartSec = 0` — the unit default is 90 s and a fat
  `@` delete can exceed it
- `boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs pkgs.util-linux ]` —
  `extraBin` only symlinks the binary, not its library closure

Ordering is the whole mechanism: the wipe must run **after**
`initrd-root-device.target` (device present) and **before** `sysroot.mount`
— once `@` is mounted, deleting it is `EBUSY`.

The script, in sequence (each numbered step is a gate that aborts to
`fail_open` on unmet expectation):

1. Mount the filesystem explicitly at **`-o subvolid=5`** — never rely on
   the default-subvolume fallback. Assert
   `btrfs subvolume get-default` still reports FS_TREE; if it does not,
   escape lane 2 has been destroyed by someone else — abort loudly.
2. Kill-switch: `impermanence.disable` on `/proc/cmdline` → log, write
   `/run/impermanence/DISABLED`, clean any stale `@new`/`@old.*`, unmount,
   exit 0. The boot proceeds on whatever root exists.
3. Guard: `@base` exists. (Without this, a delete→snapshot pair loses both.)
4. Guard: no nested subvolume inside `@` (`btrfs subvolume list` against
   its id is empty). Nested children make `subvolume delete` refuse; on
   vanilla systems that silently boots a stale `@` forever.
5. Clean stale `@new` / `@old.*` remnants from an interrupted earlier boot.
6. Wipe, atomic-ordered: `btrfs subvolume snapshot @base @new` →
   `mv @ @old` (if `@` exists) → `mv @new @` → `btrfs subvolume delete @old`
   → `sync` → unmount. Create-then-swap: any single step failing leaves a
   recoverable tree, and a re-run converges.
7. Exit 0 **always**, including the `fail_open` path. This is deliberate —
   see the decision below.

`fail_open` = log to console and `/dev/kmsg` with reason, write
`/run/impermanence/FAILED` (stage-1 `/run` is the tmpfs that survives
`switch_root`, so the marker is visible to the running system and erased on
the next boot by construction), unmount best-effort, exit 0. Boot proceeds
on the stale `@`.

**The loud half (`impermanence-check.service`, stage-2, oneshot):** reads
the stage-1 markers. If `/run/impermanence/FAILED` exists:
`log -p err` with the reason, write a node-exporter textfile metric
(`node_impermanence_wipe_failed 1`), and exit 1 — so the boot also shows
red in `systemctl --failed` and can never be mistaken for clean. If
`DISABLED`: metric 0, loud log, exit 0. This unit is the alert source;
the central VictoriaMetrics rule (`node_impermanence_wipe_failed == 1`)
lands with the monitoring-lane wiring task. Until then the failed unit and
login banner are the signal.

**Persistence binds:** declared as `fileSystems` entries (one mount
mechanism, not a mix of `fileSystems` + hand-written `.mount` units),
every one with:

- `neededForBoot = true` — without it, binds land at `local-fs.target`,
  i.e. after stage-2 `/etc` activation and racing
  nix-daemon/sshd/journald. That race is the uid-renumbering failure this
  spec names as its own justification.
- explicit `Options = [ "bind" ]` + generated `RequiresMountsFor` on
  `/persistent` (the initrd service creates nothing at runtime except
  mountpoints — see below).
- initrd-side `mkdir -p` of every bind *source* under `/persistent` in the
  wipe service, plus a stage-2 `AssertPathExists=` on each bind source.
  Mount units create the mountpoint, never the source: an allow-list entry
  whose source is missing must fail as itself, not half-mount an empty dir.

Two entries are **not** binds:

- `/var/log/journal` is its own subvolume `@journal` with
  `neededForBoot = true`. `systemd-journald` has `DefaultDependencies=no`
  and runs `Before=sysinit.target`; a bind arriving at `local-fs` loses
  that race, journald writes to the volatile runtime journal, and
  `journalctl --verify` then passes on nothing — a green check of an empty
  box.
- `/persistent` itself is a normal subvolume mount with
  `neededForBoot = true` (the binds' parent, so it must precede them).

**No `/etc` binds, and no `/etc/machine-id` bind.** Stage-2 `/etc` is an
overlayfs assembled by `init` and it shadows anything bind-mounted under
`/etc/ssh` or `/etc/machine-id`; additionally `/etc/machine-id` is read by
PID1 before `local-fs.target`, so a bind would never be the effective id
anyway. Replacements:

- Host keys: persist the *data* under `/persistent/etc/ssh` (contents
  only, not an `/etc` bind) and declare
  `services.openssh.hostKeys = [ { file = "/persistent/etc/ssh/ssh_host_ed25519_key"; } ]`.
  Seed the key into `@persistent` during migration; reseed regenerates it
  if absent.
- `machine-id`: declaratively static via `environment.etc."machine-id"`
  with this host's id committed in the config. Deterministic identity
  needs no persistence at all — the store re-renders it every activation.
  Verify during the flip boot that journald sealing still validates
  against it.

**Re-seed (`impermanence-reseed.service`, oneshot, manual start):**
create-then-swap, mirroring the wipe: mount `-o subvolid=5`, `sync`,
`btrfs subvolume snapshot -r @ @base.new`, delete `@base`,
`mv @base.new @base`. A failure at any step leaves either the old
`@base` or a complete `@base.new` — re-running converges. Honest
statement: this snapshots a live filesystem, so `@base` is
**crash-consistent, not point-in-time**. Databases on the root volume
must tolerate that; nothing on the allow-list demands more (docker data
lives on its own subvolume, never reseeded via this path).

### Persist allow-list (everything under `/persistent`, bind-mounted unless
listed as a subvolume mount)

- `/persistent/etc/ssh` (contents) — host keys via
  `services.openssh.hostKeys`. Stable identity across reboots and address
  moves.
- `/var/lib/nixos` — uid/gid identity database. Without it, users and
  service accounts renumber every boot.
- `/var/log/journal` (`@journal` subvolume) — sealed journald state and
  logs; Phase A2's seal needs persistent state, and it must be mounted
  before journald starts (see above).
- `/var/lib/systemd` — systemd-networkd DUID lives here. Without it the
  DHCP client-id changes every boot, which quietly breaks the
  controller-owned reservation that is this host's whole addressing
  premise (#11969).
- `/var/log/audit` — auditd rules write here
  (`hardening.nix:156-166`); audit records are a hardening feature and
  must not evaporate.
- `/etc/doco-cd` (contents under `/persistent`) — the parent spec's
  bootstrap secret for this host.
- `/root/nixos` — the config tree (until the host moves to a real git
  checkout of this repo — a tracked follow-up).
- `/persistent/docker` (via `@docker`) — declared Docker `data-root`.
  Requires `RequiresMountsFor=/persistent/docker` on
  `docker.service`, otherwise dockerd can initialise an empty store under
  the ephemeral root and the bind lands over it at mount time — silent
  split-brain. Boot gate verifies `docker info` reports the declared path.

Docker lane note: on top of the shared-pool caveat above, the lane lands
here; per-container capacity controls (qgroups or driver limits) are a
lane-phase decision, not a Phase B promise.

Anything else on `/` has a guaranteed lifetime of one reboot. That is the
feature.

## Decisions

### Reseed trigger — manual (unchanged)

`systemctl start impermanence-reseed` after each change that booted, ran,
and was accepted. An automatic timer (survive-N-minutes promotion) was
rejected: a config that fails at minute six gets promoted by
minute-five-plus-five. Operator ceremony is the cost; "the base is only
ever a state I approved" is the gain. The reseed unit is expected to run
in the same session that ran the switch.

### Wipe failure — fail-open to stale root, made loud

**Chosen: fail-open.** A failed wipe logs loudly, writes
`/run/impermanence/FAILED`, leaves a failed unit behind, boots the stale
`@`, and alerts through the checker metric. Fail-closed (panic/refuse
boot) was rejected: this host has no monitor and its initrd SSH is
unproven at spec time — "refuse to boot" on a headless box is indistinguishable
from "bricked" until someone physically intervenes. Stale-but-bootable
with a proven alert chain is recoverable at leisure; unreachable is not.

The decision is conditional and the condition is structural, not
aspirational: fail-open is only acceptable *because* the marker chain is
proven — the break-and-restore drill below is a migration gate, not a
follow-up. The marker alone is not enough: it must be read by the checker,
surfaced as a failed unit, and alerted on before Phase B closes.

Kill-switch: `impermanence.disable` on the kernel cmdline (editable in
systemd-boot at pick time, or via `boot.kernelParams` for a persistent
skip). Semantics: skip wipe, write `/run/impermanence/DISABLED`, boot
whatever root exists, loud log. It is a supported mode for "I know
something is wrong, boot anyway", not an escape from the allow-list
discipline.

### Rollback lane integrity — explicit mounts, `set-default` forbidden

Old generations boot FS_TREE because it is the default subvolume — the
pre-phase cmdlines carry no `subvol=`. A single
`btrfs subvolume set-default @` by anyone (human or future tooling)
destroys the lane *and* would make the wipe service try to delete the
subvolume it just mounted. Therefore:

- Every mechanism in the module mounts with `-o subvolid=5` explicitly;
  none may rely on the default.
- The wipe service asserts the default is still FS_TREE every boot and
  fail-opens loudly if it is not.
- No code path, script, or doc in this repo calls `set-default` on this
  host. Documented as invariant.
- New entries keep carrying `subvol=@` explicitly on the kernel cmdline;
  we do not "improve" the layout by changing the default.

## Escape lanes (ordered by cost)

1. **PR-A first, before any layout change:** initrd SSH, proven by a
   deliberate reboot drill. Requirements the rev-1 spec assumed were
   already true and are not:
   - NIC driver in the initrd: `e1000e` added to
     `boot.initrd.availableKernelModules` (absent today);
   - `boot.initrd.network.enable` + DHCP (`udhcpc`) so the interface is
     up stage-1;
   - non-empty `boot.initrd.network.ssh.hostKeys` — the option asserts;
     a dedicated initrd keypair is generated once, the private half
     sops-encrypted like other host secrets, referenced from the host
     module. Separate from stage-2 host keys; rotation independent.
   This is the out-of-band path if a boot ever fails before root mounts,
   and Phase C (LUKS2+TPM2) inherits it as its unlock path.
2. **Old generations stay bootable as-is** — with the integrity
   invariants above. Rollback = pick an old entry; it boots the
   pre-Phase-B FS_TREE tree untouched (new subvolumes are siblings, the
   migration never deletes or moves the top-level tree).
3. Physical console (present for the flip and drill reboots).

## Migration sequence (one host, one window, deliberate)

1. **PR-A: initrd SSH.** Add `e1000e`, initrd network + DHCP + host keys.
   `nixos-rebuild boot`, reboot, **prove** the 2222 shell while `/` is
   unmounted. No layout work merges before this drill passes.
2. Create subvolumes beside the live system from FS_TREE: `@`,
   `@persistent`, `@docker`, `@journal`. Seed `@`:
   `rsync -aHAXSx --numeric-ids` with an **explicit exclude list** —
   `/mnt`, `/nix`, `/home`, `/boot`, `/proc`, `/sys`, `/dev`, `/run`,
   `/tmp`, `/var/tmp`, `/var/lib/docker`. Explicit, because `/mnt/@`
   sitting inside a scanned tree recurses on the second run, and `-x`
   does *not* exclude sibling subvolumes (they share the fsid).
   Seed allow-list contents into `@persistent` (host key, nixos dir,
   DUID dir, doco-cd secret). `@journal` starts empty. Docker has no
   containers yet — the lane was deliberately deferred behind this
   phase, so no runtime data moves.
3. Snapshot `@` → `@base` (read-only).
4. **PR-B:** import `impermanence-btrfs.nix` + a new **hand-owned**
   host-fs module for the layout. `hardware-bifrostix.nix` keeps its
   "do not modify" contract; layout overrides live beside it, not in it.
   Contents per Design: `fileSystems` entries for `/` (`subvol=@`),
   `/persistent`, `/persistent/docker`, `/var/log/journal`;
   `boot.tmp.useTmpfs` (a hand-rolled tmpfs entry is 0755 and
   RAM-unbounded); zram stays as-is; Docker `data-root` +
   `RequiresMountsFor`; wipe + checker + reseed units.
   Gate: eval + `--dry-run` build at the pin.
5. `nixos-rebuild boot` (**not** `switch` — the root-mount flip, the bind
   cascade, and sshd ordering are boot-time concerns).
6. **Boot gate (irreversible-by-choice, reversible-by-lane):** reboot,
   verify:
   - `findmnt /` shows `subvol=@`; `mountpoint -q` passes for
     `/persistent`, `/persistent/docker`, `/var/log/journal`, every
     allow-list bind;
   - `docker info` reports `Docker Root Dir: /persistent/docker`;
   - 0 failed units; sshd / docker / networkd / nftables active;
   - `journalctl --verify` clean **and non-vacuous** — entries exist
     under `/var/log/journal` (the rev-1 trap: a green check of a
     volatile empty journal).
7. **Break-and-restore drill (gate for the fail-open decision):**
   plant `touch /root/ephemeral`; from a live session rename `@base` →
   `@base.off`; reboot. Expected and verified: boot succeeds on stale
   `@`, `/run/impermanence/FAILED` present,
   `systemctl --failed` lists `impermanence-check`, the marker reason is
   in the journal, and `/root/ephemeral` **survives** (proof the wipe
   correctly skipped). Then restore `@base.off` → `@base` and reboot:
   expected: marker absent, no failed units, `/root/ephemeral` **gone**
   (first real wipe), allow-list paths survive, host-key fingerprint
   unchanged. This one drill is simultaneously the fail-open proof, the
   first wipe proof, and the `@base` restore drill.
8. Reseed: `systemctl start impermanence-reseed` — the base now equals
   the approved state, read-only.
9. Cleanup pass (later PR): delete `tmp`, `var/tmp`,
   `var/lib/{portables,machines}`, `srv` subvolumes; drop the old
   top-level tree once Phase C no longer needs the old-generation
   rollback lane. Same PR: fix the stale
   `docs/backstage/systems/bifrostix/docs/index.md` (still says 26.05 /
   `f1e5c35` / `.232`).

Planned reboots to close Phase B: four — PR-A drill (1), the flip (2),
the break (3), the restore-and-first-wipe (4). Each is self-recovering by
design, and the fail-open path is what makes "self-recovering" a claim
the drill has actually tested.

## Non-goals for this spec

- LUKS2 + TPM2 enrollment (Phase C, next: initrd SSH unlock +
  `systemd-cryptenroll` on this layout).
- `@snapshots` history / snapper-style roll-forward. Single base +
  generation-rollback covers the need; history can land later beside it.
- Host git-checkout (config source) — separate follow-up.
- qgroups / per-container capacity limits — docker-lane phase.
- `/home` impermanence treatment. The pilot runs no interactive login
  work today (root only; the `nils` user from the docker-lane parent
  exists and needs a working home at runtime — revisit with the lane,
  where per-container users land).
- `stateVersion` stays `26.05` — no behavior change is being requested
  from this migration.

## How to verify

- After PR-A: an initrd shell on port 2222, reachable while `/` is not
  yet mounted (proven during the drill reboot), authenticating with the
  dedicated initrd key.
- After step 6: every `findmnt`/`mountpoint` assertion above passes on
  the live boot, not just in the rendered config.
- After step 7 (both reboots): fail-open behaves as specified — FAILED
  marker + failed unit + stale root + marker file survives — and the
  restore reboot proves the wipe and persistence in one stroke:
  ephemeral gone, every allow-list path present, host-key fingerprint
  unchanged, `journalctl --verify` clean on a non-empty
  `/var/log/journal`.
- Static invariants: no `set-default` anywhere in the repo's nixos tree
  for this host (grep-gate in PR-B CI alongside the existing
  nix-evaluation check); wipe service asserts
  `btrfs subvolume get-default` every boot.
- `btrfs filesystem usage` recorded before the flip and at the close, to
  catch a leak between `@` and persistent subvolumes early.
