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
  sentinelCheck = s:
    let p = "\${M}/@persistent/${s.path}";
    in
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
    else if s.check == "present" then ''
      if [ ! -d "${p}" ]; then
        halt "persist sentinel missing: @persistent/${s.path}"
      fi
    ''
    else throw "impermanence: unknown sentinel check '${s.check}'";

  persistBindSrcs = map (b: "\${M}/@persistent${b}") cfg.persistBinds;

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
      echo "impermanence-wipe: HALT: $1 — refusing to boot, reach initrd SSH on :2222"
      echo "impermanence-wipe: HALT: $1 — refusing to boot, reach initrd SSH on :2222" > /dev/kmsg 2>/dev/null || true
      mkdir -p "$MARK"
      printf '%s' "$1" > "$MARK/FAILED"
      umount "$M" 2>/dev/null || true
      # 2026-11-17: 26.11's chain walks PAST a failed wipe unit (proven
      # 12:5x: 2222 open one minute, gone). Park for real: isolate to
      # emergency.target — it kills the pending switch-root progression
      # and fires the initrd black-box recorder (dumps + reboots itself,
      # landing on the gen26-pinned EFI default).
      systemctl isolate emergency.target || true
      exec sleep infinity
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

    # 5. Sentinels gate the mkdir. The wipe itself creates missing bind
    # sources, so an assert *after* the mkdir would be vacuous — this is the
    # only order in which the sentinel has teeth.
    ${lib.concatStringsSep "\n" (map sentinelCheck cfg.sentinelDirs)}
    mkdir -p ${lib.concatStringsSep " " persistBindSrcs}

    # 6. Guard @base. Without a seed, a delete -> snapshot pair loses both.
    [ -d "$M/@base" ] || fail_open "no @base seed present"

    # 7. Guard no nested subvolume inside @. Nested children make
    # `subvolume delete` refuse, silently booting a stale @ forever.
    # NB: `list <path>` without -o lists the WHOLE filesystem — only -o
    # filters to children of the given subvolume (proven live 2026-11-17).
    if [ -n "$(btrfs subvolume list -o "$M/@")" ]; then
      fail_open "nested subvolume(s) under @ — wipe cannot proceed"
    fi

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
    btrfs subvolume delete "$M/@old" >/dev/null 2>&1 \
      || echo "impermanence-wipe: could not delete @old (boot is unaffected)"
    # A completed wipe from @base is a clean root — a stale FAILED must not
    # report a clean boot as failed.
    rm -f "$MARK"/* 2>/dev/null || true
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
    boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux ];

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
