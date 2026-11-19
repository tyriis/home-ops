# New Node Install

Proven end-to-end with util02 (ZimaBlade), 2026-11-19: USB maintenance boot →
`task talos:install` → Ready node in 82 s.

## Steps

1. Boot the node from the metal installer USB (schematic + version from
   `talos/utility/schematic.yaml` / `version.yaml`). The console prints IP,
   gateway and — crucially — the maintenance **cert fingerprint**
   (`server certificate issued … fingerprint "<b64>"`). The fingerprint is
   minted per boot.
2. Render + apply from a workstation:

   ```sh
   task talos:install cluster=utility node=<name> ip=<dhcp-ip> role=worker
   ```

3. Watch progress from the workstation — the maintenance API answers reads
   over the insecure transport, no talsecret or talosconfig needed:

   ```sh
   talosctl get unattendedinstallstatuses --insecure --cert-fingerprint '<fp>' --nodes <ip>
   ```

   Phases: `pending` → `installing` → `installed` → `waiting-for-reboot`.
   Then `kubectl --context readonly@utility get nodes`.

## Pitfalls that cost hours (util02, 2026-11-19)

- **`disk.serial` does not exist on this board.** ZimaBlade's ahci surfaces no
  serial attribute on either SATA port — Kingston's serial only appears
  inside its wwID, and the Samsung's wwID is a vendor NAA that does not
  contain its serial at all. A selector matching an empty attribute produces
  **no error**: the install sits in `pending` forever. Always read
  `talosctl get disks -o yaml` from the maintenance boot FIRST and pick
  selectors from attributes that actually exist — prefer wwID.
- **eMMC trap.** The ZimaBlade carries a 31 GB eMMC with old ZimaOS. A
  selector-less or loose install grabs it first.
- **Worker machine configs reject control-plane documents.** `cluster.etcd`,
  `KubeControllerManagerConfig`, `KubeSchedulerConfig`, `KubeProxyConfig`,
  `KubeTalosAPIAccessConfig` are control-plane-only — they live in
  `common-cp.patch.yaml`, which `render-config.sh` applies only for
  `role=controlplane`. A worker render must not contain them.
- **Console noise to ignore.** `error evaluating disk locator: no such
attribute(s): system_disk` plus services looping `Waiting` during a
  maintenance boot is normal pre-install state (upstream-confirmed). Trust
  only `UnattendedInstallStatus` phases.
- **Installer image is derived** at render time from schematic + version — do
  not pin it in node patches.

## After join

- Record wwIDs + MAC in the disk inventory / this page; reserve the DHCP
  address.
- Regenerate the client config:
  `task talos:talosconfig cluster=utility nodes="192.168.100.31 <new-ip>"`
  (requires the sops identity — run from an admin shell).
- Verify: see the probe table in the [overview](index.md).
