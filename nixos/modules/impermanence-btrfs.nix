# Impermanence mechanism for btrfs docker-lane hosts.
# Design: docs/superpowers/specs/2026-11-16-bifrostix-impermanence-btrfs-design.md
#
# Root (`@`) is wiped and re-snapshotted from a read-only seed (`@base`) on
# every boot, in stage 1. Everything that must survive is a bind mount under
# `/persistent` (an allow-list), and the wipe refuses to boot open if that
# surface is empty — booting onto an empty `/var/lib/nixos` renumbers every
# uid and silently corrupts ownership across every persisted path.
#
# Per-device configuration is passed in by the host's layout module
# (`hosts/<name>-fs.nix`); this file owns only the mechanism. All mounts use
# `-o subvolid=5` explicitly — the default-subvolume fallback is never
# relied on, so the old-generation rollback lane survives. A pre-commit
# grep gate (scripts/hooks/check-nixos-default-subvol.sh) keeps it that
# way: no nixos/ code path ever changes the default.
#
# Three units:
#   impermanence-wipe   (stage 1)  — wipe + guard + fail-open/fail-closed
#   impermanence-check  (stage 2)  — reads the stage-1 markers, surfaces a
#                                    failed unit + a vmagent textfile metric
#   impermanence-reseed (stage 2)  — manual `systemctl start`; promotes a
#                                    new read-only `@base` from the live `@`
{ config, lib, pkgs, ... }:
let
  cfg = config.impermanence;

  # Scratch mount point for FS_TREE during the stage-1 wipe.
  wipeMnt = "/mnt/impermanence-wipe";
  reseedMnt = "/mnt/impermanence-reseed";

  # One shell test per sentinel; the sentinel surface is a per-device input
  # so a fresh host can seed an empty @persistent without tripping it.
  # Persist surfaces are CHILD SUBVOLUMES of @persistent (device mounts —
  # immune to sibling-mount ordering). Child-subvol content exists only
  # across the subvol's own mount: a sibling mount shows it as an empty
  # dir. Sentinels therefore mount the surface itself before checking.
  sentinelCheck = s:
    let p = "\${M}/_sentinel";
    in
    ''
      mkdir -p "${p}"
      if ! mount -o subvol=@persistent/${s.path} "$D" "${p}" 2>/dev/null; then
        halt "persist sentinel surface @persistent/${s.path} not mountable"
      fi
    '' + (
    if s.check == "nonempty" then ''
      if [ -z "$(ls -A "${p}" 2>/dev/null)" ]; then
        halt "persist sentinel empty: @persistent/${s.path}"
      fi
    ''
    else if s.check == "hostkeys" then ''
      if ! ls "${p}"/ssh_host_*_key >/dev/null 2>&1; then
        halt "persist sentinel has no host key: @persistent/${s.path}"
      fi
    ''
    else if s.check == "present" then ""
    else throw "impermanence: unknown sentinel check '${s.check}'")
    + ''
      umount "${p}" 2>/dev/null || halt "sentinel umount failed: ${s.path}"
    '';

  persistBindSrcs = map (b: "\${M}/@persistent/${b}") cfg.persistBinds;

  # Every non-ephemeral mountpoint declared anywhere in the config, so the
  # wipe can assert the shape of the root it ships (see step 10).
  allMountPoints = builtins.map (m: m.mountPoint)
    (builtins.attrValues config.fileSystems);

  wipeScript = ''
    #!/bin/sh
    set -u
    D="${cfg.device}"
    M="${wipeMnt}"
    MARK="/run/impermanence"

    # ONE-SHOT GATE (gen44, 2026-11-17). 26.11 re-queues this unit a second
    # time during initrd-cleanup — initrd-parse-etc daemon-reloads and
    # re-requests its targets, and a dead requiredBy unit on a re-triggered
    # target is started again. The gen27-43 death pattern, proven verbatim
    # from gen40's deadman dump (@persistent/debug deadman-20261117T220623):
    # run 2 renames the LIVE root @ -> @old (permitted — the mount lives at
    # /sysroot, not at @'s name entry), then run 2's @old delete sees only
    # the freshly renamed path, so btrfs's mounted-subvolume check misses it,
    # and deletes the tree that /sysroot's filesystem IS. 26.11 activation
    # then chroots and ENOENTs walking `nix` off the deleted root:
    # "prepare-root: No such file or directory", exit 127, 6.2 s in.
    # /run is initrd tmpfs: this marker is per-boot, exactly the scope
    # needed. A re-fired run must touch zero btrfs state.
    mkdir -p "$MARK"
    if [ -e "$MARK/DONE" ]; then
      echo "impermanence-wipe: re-fire suppressed (26.11 initrd re-triggers requiredBy units)"
      exit 0
    fi
    : > "$MARK/DONE"

    # Fail-open: a viable root exists, so boot it — but say so, loudly, via a
    # FAILED marker the stage-2 checker turns into a failed unit + a metric.
    fail_open() {
      echo "impermanence-wipe: fail-open: $1"
      echo "impermanence-wipe: fail-open: $1" > /dev/kmsg 2>/dev/null || true
      mkdir -p "$MARK"
      printf '%s' "$1" > "$MARK/FAILED"
      umount "$M" 2>/dev/null || true
      exit 0
    }
    # Fail-closed: "boot anyway" would be a lie (no root, or a persist
    # surface whose boot would self-corrupt). Halt and route to initrd SSH.
    halt() {
      # 26.11 lesson (12:5x + 21:2x consoles): a FAILED wipe unit does
      # NOT stop the chain, and no usable systemctl exists in the
      # initrd. Stop-attempted designs that assumed either made boots
      # silently worse. This function therefore only marks intent;
      # impermanence-halt-guard (Required-by local-fs) converts the
      # marker into a real block: guard fails -> emergency -> recorder
      # dumps reason -> auto-reboot to the pinned good generation.
      echo "impermanence-wipe: HALT: $1 — blocked by halt-guard, see recorder dump"
      echo "impermanence-wipe: HALT: $1 — blocked by halt-guard, see recorder dump" > /dev/kmsg 2>/dev/null || true
      mkdir -p "$MARK"
      printf '%s' "$1" > "$MARK/HALT"
      printf '%s' "$1" > "$MARK/FAILED"
      umount "$M" 2>/dev/null || true
      exit 0
    }

    # 1. Mount FS_TREE explicitly.
    mkdir -p "$M"
    mount -o subvolid=5 "$D" "$M" || fail_open "could not mount FS_TREE"

    # 2. Recover before anything else. A missing @ with no remnant is no
    # root — exit 0 there only buys a confusing mount error after an empty
    # shell. Recovery is terminal (boot the reconstructed @, marked stale).
    if [ ! -d "$M/@" ]; then
      if [ -e "$M/@new" ]; then
        mv "$M/@new" "$M/@" || halt "recovery: cannot promote @new"
        echo "impermanence-wipe: recovery promoted @new -> @ (stale boot)"
        mkdir -p "$MARK"; printf 'recovered: promoted @new' > "$MARK/FAILED"
        umount "$M" 2>/dev/null || true; exit 0
      elif [ -e "$M/@old" ]; then
        mv "$M/@old" "$M/@" || halt "recovery: cannot restore @old"
        echo "impermanence-wipe: recovery restored @old -> @ (stale boot)"
        mkdir -p "$MARK"; printf 'recovered: restored @old' > "$MARK/FAILED"
        umount "$M" 2>/dev/null || true; exit 0
      else
        halt "no @ and no @new/@old remnant to recover"
      fi
    fi

    # 2.5 Operator hold gate (PoC era, 2026-11-17): a flag file on
    # FS_TREE parks the boot before anything is touched. Proven escape
    # lane (2026-11-17 12:3x): a failed wipe unit lands the boot in
    # initrd with SSH alive on :2222 — exit 1 there was reached live.
    # Release from :2222: remove the flag, then reboot. No FAILED
    # marker is written — a hold is intent, not fault.
    if [ -e "$M/impermanence-hold" ]; then
      echo "impermanence-wipe: HOLD flag set — parked, initrd SSH on :2222" > /dev/kmsg 2>/dev/null || true
      umount "$M" 2>/dev/null || true
      exit 1
    fi

    # 3. Kill-switch: skip the WIPE only (recovery already ran). Also bypasses
    # the fail-closed sentinel halt — an operator who sets it owns the
    # persist surface as-is.
    case "$(cat /proc/cmdline)" in
      *impermanence.disable*)
        echo "impermanence-wipe: wipe skipped by impermanence.disable (booting current @ as-is)"
        echo "impermanence-wipe: wipe skipped by impermanence.disable" > /dev/kmsg 2>/dev/null || true
        mkdir -p "$MARK"; printf 'disabled' > "$MARK/DISABLED"
        umount "$M" 2>/dev/null || true; exit 0
        ;;
    esac

    # 4. Assert the default subvolume is still FS_TREE. Require `ID 5`
    # exactly — a substring match against a path is not a check.
    DEF="$(btrfs subvolume get-default "$M")"
    case "$DEF" in
      *"ID 5 "*) : ;;
      *) fail_open "default subvolume is no longer FS_TREE: $DEF" ;;
    esac

    # 5. Sentinels gate the ensure step below: without this order a wipe
    # that has no data would create a fresh empty surface and the
    # nonempty check would pass against the wipe's own creation.
    ${lib.concatStringsSep "\n" (map sentinelCheck cfg.sentinelDirs)}
    # 5b. Assert each persist surface is a btrfs child subvolume of
    # @persistent (gen37: device mounts; the path binds they replace
    # raced persistent.mount and killed gens 27-36). A pre-2026-11-17
    # plain dir: empty is pruned, populated HALTS for migration.
    # rmdir refuses real subvolumes — the check cannot misfire.
    for s in ${lib.concatStringsSep " " persistBindSrcs}; do
      if ! btrfs subvolume show "$s" >/dev/null 2>&1; then
        if [ -e "$s" ]; then
          rmdir "$s" 2>/dev/null \
            || halt "persist surface $s is a populated plain dir — migrate"
        fi
        btrfs subvolume create "$s" >/dev/null 2>&1 \
          || halt "cannot create persist subvolume $s"
      fi
    done

    # 6. Guard @base. Without a seed, a delete -> snapshot pair loses both.
    [ -d "$M/@base" ] || fail_open "no @base seed present"

    # 7. Guard nested subvolumes inside @ — data only. Nested children
    # make `subvolume delete` refuse, silently booting a stale @
    # forever. NB: `list <path>` without -o lists the WHOLE filesystem —
    # only -o filters to children of the given subvolume (proven live
    # 2026-11-17).
    # 262-era finding (gen46 forensics 2026-11-18): systemd creates
    # three EMPTY furniture subvolumes (/srv, /var/lib/machines,
    # /var/lib/portables) under the mounted @ root 1.9 s into
    # stage-2 — the 26.05 installer made the same trio at fs-tree
    # level (subvol IDs 258-260). gen46 boot 2 had NO machined unit
    # in its log at all, so no service disable can prevent these.
    # An empty child is wiped WITH @ — delete refuses only because
    # it is nested, so refuse is wrong for it; a child WITH data
    # would silently lose that data, so only those fail open.
    #
    # gen47 CLOSED the loop by failing, gen47 boot 2 (2026-11-18
    # 00:51): this loop first ran with real children and died
    # "sed: command not found" — GNU sed is NOT in the initrd closure
    # (initrdBin = btrfs-progs/coreutils/util-linux; sed is its own
    # package). Boot 1 hid it: zero children meant zero loop bodies.
    # Parsers in this unit are therefore restricted to bash builtins:
    # read field-slicing only (output is "ID N gen N top level N path
    # <path>" — path = field 9, furniture paths never contain spaces).
    ALLKIDS=""
    NESTED_DATA=""
    while read -r _id _n1 _gen _n2 _top _lvl _par _kw p; do
      [ -n "$p" ] || continue
      ALLKIDS="$ALLKIDS $p"
      if [ -n "$(ls -A "$M/$p" 2>/dev/null)" ]; then
        NESTED_DATA="$NESTED_DATA $p"
      fi
    done < <(btrfs subvolume list -o "$M/@" 2>/dev/null)
    if [ -n "$NESTED_DATA" ]; then
      fail_open "nested subvolume(s) WITH DATA under @ — wipe cannot proceed:$NESTED_DATA"
    fi
    # btrfs refuses to delete a parent that has ANY children, empty or
    # not — so the (proven empty) furniture must be deleted before @.
    for p in $ALLKIDS; do
      btrfs subvolume delete "$M/$p" >/dev/null 2>&1 \
        || fail_open "cannot delete empty nested child $p"
    done

    # 8. Clean stale @new/@old remnants — only here, after recovery, only
    # while @ exists. Cleaning before recovery deletes the recovery path.
    [ -e "$M/@new" ] && btrfs subvolume delete "$M/@new" >/dev/null 2>&1
    [ -e "$M/@old" ] && btrfs subvolume delete "$M/@old" >/dev/null 2>&1

    # 9. Assert both remnant names are now gone. Step 10's rename would nest
    # @ inside a surviving @old (POSIX rename-into-directory) and the wipe
    # would be dead from that boot on. This step only asserts; it runs
    # nothing.
    if [ -e "$M/@new" ] || [ -e "$M/@old" ]; then
      fail_open "@new/@old remnant survived cleaning — refusing to rename"
    fi

    # 10. Wipe. Create-then-swap: any single step failing leaves a
    # recoverable tree, and a re-run converges via recovery.
    btrfs subvolume snapshot "$M/@base" "$M/@new" || fail_open "snapshot @base -> @new failed"
    # Re-assert every mountpoint inside @new BEFORE it is published.
    # @base should carry them (it was seeded from a full root), but a
    # silently-stale @base reproduces the 2026-11-17 initrd wall
    # ("Can't look up mountpoint") three steps later where nothing can
    # see it. Cheap and decisive: assert the shape of the tree we ship.
    ${lib.concatStringsSep "\n" (map (p: ''mkdir -p "$M/@new${p}"'') (lib.unique allMountPoints))}
    [ ! -e "$M/@old" ] || fail_open "@old reappeared mid-wipe"
    mv "$M/@" "$M/@old" || fail_open "mv @ -> @old failed"
    [ -e "$M/@new" ] || fail_open "@new vanished before promote"
    mv "$M/@new" "$M/@" || fail_open "mv @new -> @ failed"
    # Never delete the subvolume that backs the live root. btrfs-progs
    # decides "is this mounted?" from mount-table PATHS, and we have
    # just renamed the path to @old — the check misses /sysroot's mount
    # and deletes the running tree (gen40 post-mortem: this exact call
    # pulled /sysroot's root out from under 26.11 activation's chroot).
    # Stat inodes are subvolume ids on btrfs and rename-invariant:
    # compare those, not names.
    OLD_INO="$(stat -c %i "$M/@old" 2>/dev/null || echo x)"
    SYS_INO="$(stat -c %i /sysroot 2>/dev/null || echo y)"
    if [ "$OLD_INO" = "$SYS_INO" ]; then
      echo "impermanence-wipe: @old is the live /sysroot root — delete skipped (26.11 guard)"
    else
      btrfs subvolume delete "$M/@old" >/dev/null 2>&1 \
        || echo "impermanence-wipe: could not delete @old (boot is unaffected)"
    fi
    # A completed wipe from @base is a clean root — a stale FAILED must not
    # report a clean boot as done-failed. Do NOT glob: the DONE one-shot
    # marker above must survive this line, or a 26.11 re-fire re-arms and
    # re-runs the full wipe (exactly the gen27-43 failure).
    rm -f "$MARK/FAILED" "$MARK/HALT" 2>/dev/null || true
    sync
    umount "$M" 2>/dev/null || true
    exit 0
  '';

  reseedScript = ''
    #!/bin/sh
    set -u
    D="${cfg.device}"
    M="${reseedMnt}"

    die() { echo "impermanence-reseed: $1" >&2; umount "$M" 2>/dev/null || true; exit 1; }

    mkdir -p "$M"
    mount -o subvolid=5 "$D" "$M" || die "could not mount FS_TREE"
    sync

    # 2. Reconcile all three names. A crash between the two renames leaves
    # the tree as .old; promoting it is the convergence.
    if [ ! -e "$M/@base" ]; then
      if [ -e "$M/@base.new" ]; then
        mv "$M/@base.new" "$M/@base" || die "promote @base.new"
        [ -e "$M/@base.old" ] && btrfs subvolume delete "$M/@base.old" >/dev/null 2>&1
      elif [ -e "$M/@base.old" ]; then
        mv "$M/@base.old" "$M/@base" || die "promote @base.old"
        [ -e "$M/@base.new" ] && btrfs subvolume delete "$M/@base.new" >/dev/null 2>&1
      else
        die "nothing to promote and no @base"
      fi
    else
      [ -e "$M/@base.new" ] && btrfs subvolume delete "$M/@base.new" >/dev/null 2>&1
      [ -e "$M/@base.old" ] && btrfs subvolume delete "$M/@base.old" >/dev/null 2>&1
    fi

    # 3. Assert neither remnant name exists — otherwise the next
    # `mv @base @base.old` nests @base inside a stale @base.old.
    [ ! -e "$M/@base.new" ] && [ ! -e "$M/@base.old" ] || die "remnant still present after reconcile"

    # 4. Snapshot the live @ read-only.
    btrfs subvolume snapshot -r "$M/@" "$M/@base.new" || die "snapshot @ -> @base.new"

    # 5. Rename @base out of the way, guarded.
    [ ! -e "$M/@base.old" ] || die "@base.old present before swap"
    if [ -e "$M/@base" ]; then
      mv "$M/@base" "$M/@base.old" || die "mv @base -> @base.old"
    fi

    # 6. Swap the new seed into place.
    mv "$M/@base.new" "$M/@base" || die "mv @base.new -> @base"

    # 7. Delete-last.
    [ -e "$M/@base.old" ] && btrfs subvolume delete "$M/@base.old" >/dev/null 2>&1

    umount "$M" 2>/dev/null || true
    echo "impermanence-reseed: @base is now a read-only snapshot of the live @"
    exit 0
  '';
in
{
  options.impermanence = {
    enable = lib.mkEnableOption "btrfs impermanence (wipe @ from @base each boot)";

    device = lib.mkOption {
      type = lib.types.str;
      description = "Btrfs filesystem device (a stable /dev/disk/by-uuid path).";
    };

    persistBinds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Absolute mount points bound from /persistent (e.g. /var/lib/nixos).
        The wipe pre-creates the source of each at
        /persistent/<path>. Each must have a matching fileSystems entry
        declared by the host layout module.
      '';
    };

    sentinelDirs = lib.mkOption {
      type = with lib.types; listOf (submodule {
        options = {
          path = lib.mkOption { type = str; description = "Path relative to @persistent."; };
          check = lib.mkOption {
            type = enum [ "nonempty" "hostkeys" "present" ];
            description = "Sentinel assertion: dir non-empty, holds an ssh_host_*_key, or merely present.";
          };
        };
      });
      default = [ ];
      description = "Persist-surface sentinels. An empty/missing one halts the boot (fail-closed).";
    };
  };

  config = lib.mkIf cfg.enable {
    # NB: do NOT add pkgs.systemd here — the build rejects it, and the
    # 21:2x console proved the dependency class (readline et al missing
    # from the 26.11 initrd closure). halt() no longer calls systemctl at
    # all: it writes a HALT marker and the impermanence-halt-guard unit
    # below fails the chain into emergency. Use the chain, not binaries.
    boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux ];

    # Fail-closed enforcer. The 26.11 chain walks PAST a failed wipe
    # unit (proven 12:5x and 21:2x), so halt() alone cannot stop a boot.
    # This unit closes that hole with zero external binaries: it is
    # Required-by local-fs, runs after the wipe, and exits 1 iff the
    # wipe wrote a HALT marker. Its failure drags local-fs down ->
    # initrd emergency.target -> the black-box recorder dumps the
    # reason to ESP + @persistent/debug -> ExecStartPost reboots to the
    # gen26-pinned EFI default. Fail-open's FAILED marker deliberately
    # does NOT trip this gate — only HALT does.
    boot.initrd.systemd.services."impermanence-halt-guard" = {
      description = "Impermanence: block local-fs when the wipe halted";
      requiredBy = [ "local-fs.target" ];
      after = [ "impermanence-wipe.service" ];
      before = [ "local-fs.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ -e /run/impermanence/HALT ]; then
          echo "impermanence-halt-guard: wipe HALTED — forcing emergency" > /dev/kmsg 2>/dev/null || true
          exit 1
        fi
      '';
    };

    # Stage 1: the wipe. Order is the whole mechanism — after the root device
    # is present, before sysroot mounts it (deleting a mounted @ is EBUSY).
    boot.initrd.systemd.services."impermanence-wipe" = {
      description = "Impermanence: wipe @ and re-snapshot from @base";
      after = [ "initrd-root-device.target" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      requiredBy = [ "initrd-root-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        # The unit default is 90 s; a fat @ delete can exceed it.
        TimeoutStartSec = 0;
      };
      script = wipeScript;
    };

    # 2026-11-17 RETRACTED: an earlier build of this module added
    # After=+Requires=initrd-fs.target to initrd-nixos-activation on the
    # theory that /sysroot/nix was slow to appear. That theory was wrong
    # (gen32 carried the fix and still died) and the change pulled
    # activation's dependency subtree EARLIER, worsening the very race:
    # the real starvation was device arrival, and x-initrd ordering is
    # owned by the 26.11 fstab-generator with proper .device deps. Do not
    # re-assert ordering edges on stock initrd units from here.

    # Stage 2: the loud half. Never mistaken for a clean boot.
    systemd.services.impermanence-check = {
      description = "Impermanence: report the stage-1 wipe marker";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        FAILED=/run/impermanence/FAILED
        DISABLED=/run/impermanence/DISABLED
        TEXT=/var/lib/impsnap/impermanence-status.prom
        mkdir -p /var/lib/impsnap
        if [ -e "$FAILED" ]; then
          echo "node_impermanence_wipe_failed 1" > "$TEXT"
          echo "impermanence: wipe did not complete cleanly: $(cat "$FAILED")"
          exit 1
        elif [ -e "$DISABLED" ]; then
          echo "node_impermanence_wipe_failed 0" > "$TEXT"
          echo "impermanence: wipe skipped by impermanence.disable kill-switch"
        else
          # A metric written only on failure latches at 1 forever; a clean
          # boot must re-assert 0.
          echo "node_impermanence_wipe_failed 0" > "$TEXT"
        fi
      '';
    };

    # 26.11 socket-activates the machined/portabled/importd trio by
    # default, and machined auto-creates its storage as btrfs SUBVOLUMES
    # under the live @ when triggered: gen44 boot 1 grew exactly three
    # new @ children (machines, portables, srv) two seconds after
    # "Listening on Virtual Machine and Container Registration Service
    # Socket", and boot 2's nested-child guard refused to wipe a tree
    # the wipe design does not know how to reason about. The docker
    # lane talks to none of them; a guard that trips on a unit nobody
    # wants is a guard that will be weakened. Disabled at socket level
    # (the trigger) and service level for symmetry.
    systemd.services."systemd-machined".wantedBy = lib.mkForce [];
    systemd.services."systemd-portabled".wantedBy = lib.mkForce [];
    systemd.services."systemd-importd".wantedBy = lib.mkForce [];
    systemd.sockets."systemd-machined".wantedBy = lib.mkForce [];
    systemd.sockets."systemd-portabled".wantedBy = lib.mkForce [];
    systemd.sockets."systemd-importd".wantedBy = lib.mkForce [];

    # 46's own battery (boot 1, 2026-11-18) proved the six lines above
    # are necessary but not sufficient: the .wants symlinks are 26.11
    # GENERATION content (Jan-1970 timestamps — they ship with the
    # build, not stale drift), so `is-enabled` still says enabled even
    # though the generated units have no [Install] section. Boot 2
    # proved the mkForce does keep the services from RUNNING (zero
    # machined log lines) — the residue is enablement only. This unit
    # makes that residue self-healing: every activation, sever any
    # enablement and stop anything socket-activated. Idempotent by
    # `|| true` — absent units are the success case.
    systemd.services."impermanence-machined-containment" = {
      description = "Impermanence: sever machined/portabled/importd enablement";
      wantedBy = [ "basic.target" ];
      after = [ "basic.target" ];
      before = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        for u in systemd-machined systemd-portabled systemd-importd; do
          systemctl disable --now "$u.socket" "$u.service" >/dev/null 2>&1 || true
        done
      '';
    };

    # Stage 2: manual re-seed. No wantedBy — an operator command only.
    systemd.services.impermanence-reseed = {
      description = "Impermanence: promote a new read-only @base from the live @ (manual)";
      path = [ pkgs.btrfs-progs pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = reseedScript;
    };
  };
}
