# Talos Native Machineconfig Migration (retire talhelper)

**Date:** 2026-08-21
**Issues:** [#8767](https://github.com/tyriis/home-ops/issues/8767)
**Scope:** talos, talhelper, talosctl, openbao

## Overview

Retire `talhelper` (the third-party Talos config generator) and move to the official, native `talosctl` machineconfig workflow, with all Talos secrets living in OpenBao (Vault). The driver is security issue #8767: decrypted talhelper `talsecret.sops.yaml` files are readable by agents on the local system, and there is no way to prevent that. The goal is to work without plaintext/decryptable Talos secrets ever sitting on the local filesystem or in git.

This spec covers the **main** cluster (`talos/main`, Talos cluster name `main`) first. The `utility` cluster (`talos/utility`) is a near-identical repeat performed later.

> **Naming note:** `kube-lab` is a legacy name for this cluster; it is now called `main`. All vault paths and the Talos `clusterName` in this spec use `main`. The broader `kube-lab` → `main` rename (Flux `FLUX_CLUSTER_NAME`, OpenBao k8s auth role/mount, external-dns `txtOwnerId`/`txtPrefix`, CNPG S3 path, backstage helper) is **out of scope** and tracked as a separate follow-up. The Talos `clusterName` does not need to match `FLUX_CLUSTER_NAME`.

## Goals

- Remove `talhelper` entirely from the repository (tool pin, `talconfig.yaml`, `talsecret.sops.yaml`, task steps).
- Store all Talos secrets in OpenBao; git contains zero secret material.
- Keep the operator workflow as `task talos:*` + `talosctl`, using the official `talosctl gen config` / `gen secrets` / `apply-config` flow.
- Preserve the existing cluster identity — do **not** rotate/regenerate secrets.
- Keep the Image Factory schematic (system extensions + kernel args) intact.

## Non-goals

- The `utility` cluster (deferred; repeated later).
- Introducing Omni or any new Talos-management platform.
- Auto-applying Talos config from inside the cluster (an in-cluster Talos admin credential is an anti-pattern).

## Current state

| Location | Contents |
|---|---|
| `talos/main/talconfig.yaml` | talhelper input: node matrix, schematic, patches, versions (`talosVersion v1.13.8`, `kubernetesVersion v1.36.3`) |
| `talos/main/talsecret.sops.yaml` | SOPS/age-encrypted secrets bundle (talhelper `gensecret` output) |
| `talos/main/machineconfig.yaml` | Partial native draft (single controlplane config) with `vault://` placeholders — not consumable by Talos as-is |
| `.taskfiles/talos/Taskfile.yaml` | `init` (`talhelper gensecret`), `config` (`talhelper genconfig`), `install:*`, `update:*`, `bootstrap`, `kubeconfig`, `upgrade` |
| `.mise.toml` | `talhelper = 3.1.16`, `talosctl = 1.13.9`, `sops`, `age`, `openbao`/`bao` |

Cluster facts (main): endpoint `https://192.168.100.100:6443`; three control-plane nodes `talos01` (`.101`), `talos02` (`.102`), `talos03` (`.103`); `allowSchedulingOnControlPlanes: true` (no worker nodes); CNI `none`; bonded 10GbE + VLANs.

## Key decisions

1. **Secrets injection** — render from OpenBao at apply time. Git holds only base config + patches; the secrets bundle is pulled from Vault into a transient temp file, used, then deleted.
2. **Apply mechanism** — operator-driven `talosctl` via `task talos:*` (unchanged ergonomics).
3. **Scope** — main cluster first, utility later.
4. **Local-file strictness** — no committed secrets; transient temp files during apply are acceptable and cleaned up.
5. **Bootstrap / DR** — OpenBao is the sole source of truth; recovery relies on OpenBao's own snapshot/backup mechanism. No SOPS copy is retained in git.

## Secret model

The existing `talsecret.sops.yaml` is talhelper's wrapper around `talosctl gen secrets` — its decrypted content **is** the native secrets bundle (`cluster`, `trustdinfo`, `secrets`, `certs` keys). The migration therefore **migrates** these secrets into OpenBao rather than regenerating them, preserving cluster identity.

Target OpenBao location (KV v2, mount `infra`):

```
infra/techtales/talos/main/secrets   # whole `secrets.yaml` bundle as a single `data` value
```

Write / read:

```bash
bao kv put -mount=infra techtales/talos/main/secrets data="$(cat secrets.yaml)"
bao kv get -mount=infra -field=data techtales/talos/main/secrets > secrets.yaml
```

`machine.token` / `machine.ca` / `cluster.*` secret fields are **not** stored in git; `talosctl gen config --with-secrets secrets.yaml` injects them at generation time.

> **Access constraint — user-run steps.** The orchestrator/agents do **not** have `bao` or `talosctl` cluster access. Seeding OpenBao (`bao kv put`) and every `talosctl` command in the migration are **manual steps the operator runs**, supplied here as a runbook. The agents author the config/patch/taskfile files and the runbook; they never execute the secret write or the node apply. This spec assumes the secret already exists in OpenBao at the path above.

## Schematic (Image Factory)

There is no `talosctl` factory subcommand; the schematic is created via the factory HTTP API (deterministic — same YAML → same ID):

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/i915
      - siderolabs/intel-ucode
      - siderolabs/thunderbolt
  extraKernelArgs:
    - apparmor=0
    - init_on_alloc=0
    - init_on_free=0
    - intel_iommu=on
    - iommu=pt
    - mitigations=off
    - security=none
    - talos.auditd.disabled=1
```

```bash
curl -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics  # → {"id":"<sha256>"}
```

The schematic ID is baked into the install image reference `factory.talos.dev/metal-installer-secureboot/<SCHEMATIC>:<TALOS_VERSION>`. Note: for SecureBoot/UKI, `extraKernelArgs` are baked into the signed payload and cannot be overridden later by machine-config patching, so they must be correct in the schematic.

## Target layout — `talos/main/`

```
talos/main/
├── patches/
│   ├── all.yaml            # shared machine+cluster config (from current machineconfig.yaml, minus secrets)
│   ├── controlplane.yaml   # CP-specific: etcd, controlPlane.endpoint, certSANs, apiServer, scheduler
│   ├── talos01.yaml        # per-node: hostname, static IP, install disk serial, nodeLabels
│   ├── talos02.yaml
│   └── talos03.yaml
├── schematic.yaml          # Image Factory customization (committed, non-secret)
└── clusterconfig/          # generated, gitignored (controlplane.yaml, worker.yaml, talosconfig)
```

Deleted: `talconfig.yaml`, `talsecret.sops.yaml`, `machineconfig.yaml` (draft, superseded).

## Taskfile mapping

| Current (talhelper) | New (native) |
|---|---|
| `init` → `talhelper gensecret` + `sops -e` | `init` → `talosctl gen secrets` → `bao kv put` into OpenBao |
| `config` → `talhelper genconfig` | `config` → `bao kv get` bundle → `talosctl gen config --with-secrets ... --config-patch @patches/*` |
| `install:*`, `update:*`, `bootstrap`, `kubeconfig` | unchanged (already native `talosctl`) |
| `upgrade`, `kubelet:upgrade` (read versions from talconfig via yq) | read from a small committed `versions` value or `--talos-version`/`--kubernetes-version` flags |

## Operator workflow after migration

```bash
task talos:config                  # Vault → temp secrets → gen config → clusterconfig/ (temp cleaned)
task talos:install:talos01         # talosctl apply-config --insecure --nodes .101 --file controlplane.yaml --config-patch @patches/talos01.yaml
task talos:bootstrap               # talosctl bootstrap --nodes .101
task talos:kubeconfig              # talosctl kubeconfig (merge into ~/.kube/config)
task talos:update:talos01          # talosctl apply-config --nodes .101 --file ... --config-patch @patches/talos01.yaml
task talos:upgrade                 # talosctl upgrade / upgrade-k8s
```

Interactive: `talosctl dashboard`, `talosctl health`, `talosctl patch machineconfig`, `talosctl edit machineconfig`, `talosctl logs <svc>`, `talosctl containers -n kube-system`. `talosconfig` (client certs, no cluster secrets) lives in `clusterconfig/talosconfig`; endpoints = VIP `192.168.100.100`, nodes = the three node IPs.

## Migration steps (main cluster)

1. **Schematic**: create `schematic.yaml` from the current talconfig customization; `curl -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics` to obtain the deterministic ID; bake it into the install image reference. No schematic ID is committed anywhere — it is always derived.
2. **Secrets → OpenBao** *(operator-run)*: decrypt `talsecret.sops.yaml`, verify it contains the full bundle, `bao kv put` it to `infra/techtales/talos/main/secrets`. Do not regenerate.
3. **Patches**: split the draft `machineconfig.yaml` into `patches/all.yaml` + `patches/controlplane.yaml` (strip all secret fields); author per-node patches (`talos01/02/03`) from the talconfig node matrix (hostname, IP, disk serial, labels).
4. **Taskfile**: rewrite `init`/`config`/`upgrade` to native `talosctl` + `bao`; keep the rest.
5. **Validate** (no apply): `task talos:config` then `talosctl validate --config clusterconfig/controlplane.yaml --mode metal`.
6. **Apply**: `task talos:install:talos01` … `:talos03`, then `task talos:bootstrap`.
7. **Retire**: delete `talconfig.yaml`, `talsecret.sops.yaml`, the draft `machineconfig.yaml`, and the `talhelper` mise pin.
8. **Verify**: `talosctl health`; confirm Flux reconciles; `task talos:kubeconfig` works.

## Risks & mitigations

- **Secret loss / DR**: OpenBao is the sole source; ensure OpenBao snapshots/backups are verified before deleting `talsecret.sops.yaml`.
- **Schematic kernel args**: SecureBoot/UKI bakes `extraKernelArgs`; a wrong schematic ID forces a node reinstall. Validate before apply.
- **`clusterName`**: talconfig and the canonical name are `main`; the legacy `kube-lab` appears in the draft and some repo references. Use `main` for `clusterName`, the vault path, and the `talosctl` context name.
- **`{{ ENV.* }}` templating** in the draft (`TALOS_SCHEMATIC`, `TALOS_VERSION`, `KUBERNETES_VERSION`) is not native — replace with explicit values in patches/flags.

## Alternative approaches considered

Beyond the chosen "Vault as source of truth, render at apply time" model, other approaches to the core challenge (no plaintext Talos secrets readable on the operator workstation) were evaluated:

1. **OpenBao/Vault, pull at apply time** *(chosen)* — secrets never enter git; pulled transiently into a temp file at apply. Fits because OpenBao is already the house secret store.
2. **Flux Kustomize SOPS in-cluster decryption** — Flux's `kustomize-controller` decrypts SOPS-encrypted files using an age/PGP key held as a cluster `Secret` (`.sops.yaml` + `flux create secret`). The encrypted bundle stays in git, but decryption happens in-cluster, not on the workstation. Caveat: Talos machine config is not a Kubernetes object, so Flux can't apply it — a Job/operator would still need to consume the decrypted secret, reintroducing an in-cluster Talos credential.
3. **Offline/hardware-backed age key** — keep the SOPS bundle in git but move the age private key off the workstation (YubiKey / air-gapped device). Agents can't decrypt without it; minimal infra change, but the key must be present for every apply.
4. **Omni (Sidero)** — manages config + secrets entirely out-of-band; `talosctl apply-config` is blocked. Fullest but biggest architectural shift (explicitly out of scope).
5. **External Secrets Operator / Sealed Secrets** — for in-cluster K8s runtime secrets (e.g. a `talosconfig` mounted into a drift-detection Job), not for node-level machine config itself.

The industry split is really "secrets out of git (Vault/ESO)" vs "secrets encrypted in git, decrypted out-of-band (SOPS + hardware key / in-cluster)". OpenBao already runs here, so Vault is the natural, cleanest fit and satisfies "no plaintext on the workstation."

## Resolved decisions

- **Schematic ID**: not committed anywhere — derived deterministically from `schematic.yaml` via `curl -X POST https://factory.talos.dev/schematics`. Same customization → same ID as installed on the nodes.
- **`kube-lab` → `main` rename**: Talos-only (`clusterName` + vault path). The remaining `kube-lab` references (Flux `FLUX_CLUSTER_NAME`, OpenBao auth role/mount, external-dns `txtOwnerId`/`txtPrefix`, CNPG S3 path, backstage helper) are out of scope and tracked as a separate follow-up.

## References

- [Talos Image Factory](https://docs.siderolabs.com/talos/v1.13/learn-more/image-factory)
- [Reproducible machine configuration](https://docs.siderolabs.com/talos/v1.12/configure-your-talos-cluster/system-configuration/reproducible-machine-configuration)
- [talosctl CLI reference](https://docs.siderolabs.com/talos/v1.13/reference/cli)
- [Editing machine configuration](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/system-configuration/editing-machine-configuration)
- [OpenBao kv command](https://github.com/openbao/openbao/blob/main/website/content/docs/commands/kv/index.mdx)
