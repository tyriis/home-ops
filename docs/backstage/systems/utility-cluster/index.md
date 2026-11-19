# utility-cluster

Two-node Talos cluster on the `192.168.100.0/24` segment. Runs the services the
main cluster must not own: registry, identity, secrets, git.

- Talos v1.14.6 / Kubernetes v1.37.2, single control plane, no HA by design.
- Kube endpoint: `https://192.168.100.30:6443` (kubectl context
  `readonly@utility`).
- Config pipeline: `task talos:render|dry|install cluster=utility node=<name>
[role=controlplane|worker]` — secrets decrypt at render time, nothing on
  disk (`.taskfiles/talos/`).

## Nodes

| Node   | Hardware                                  | Role          | Address                                        | OS disk                      | Data disk                                                            |
| ------ | ----------------------------------------- | ------------- | ---------------------------------------------- | ---------------------------- | -------------------------------------------------------------------- |
| util01 | Intel NUC7i7DNHE (i7-8650U, 32 GB)        | control-plane | 192.168.100.31                                 | 500 GB SSD (system)          | planned: 500 GB EVO as `data` user volume                            |
| util02 | IceWhale ZimaBlade (Celeron N3450, 16 GB) | worker        | 192.168.100.32 (DHCP, MAC `00:e0:4c:2a:16:54`) | 480 GB Kingston SA400S37480G | 500 GB Samsung 870 EVO — Talos user volume `data` at `/var/mnt/data` |

Both util02 disks are pinned by **wwID**, not serial (`talos/utility/patches/
util02.patch.yaml`): this board exposes no `disk.serial` attribute, and a
serial selector silently never matches. See [install notes](install.md).

## Workload placement

- util01: etcd + control plane, Flux, OpenBao, Pocket-ID, Harbor (until the
  storage-class migration completes).
- util02: target for Forgejo (+ Postgres), Opengist, and the observability
  stack — planned, not migrated yet.
- Migration gate: the data-bearing move (Forgejo databases) is the only step
  gated on a fresh volsync backup; observability and Harbor re-provision empty.

## Verify live state

| Fact                 | Probe                                                                                     |
| -------------------- | ----------------------------------------------------------------------------------------- |
| Nodes Ready          | `kubectl --context readonly@utility get nodes -o wide`                                    |
| util02 `data` volume | `talosctl --context utility -n 192.168.100.32 get volumestatus \| grep u-data`            |
| Node disk identity   | `talosctl --context utility -n 192.168.100.32 get disks -o yaml` (compare wwIDs to table) |
| util02 IP lease      | UniFi controller — reservation for `00:e0:4c:2a:16:54` (status: pending)                  |
