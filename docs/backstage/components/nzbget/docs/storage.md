# Storage

No app data writes to node disk. Data lives on the Ceph config PVC, the NAS, or in RAM.

## Config PVC (Ceph, persistent)

| Path          | Content                              |
| ------------- | ------------------------------------ |
| `nzbget.db`   | Queue and history database           |
| `nzbget.conf` | Settings, changed through the web UI |
| `nzbget.log`  | App log file                         |

VolSync replicates the PVC to MinIO (`backup-system`).

## Media (NFS)

The NAS share `nas.techtales.io:/mnt/tank/media` is mounted read-write.
Downloads and post-processing write directly there, not to node disk.

## RAM (tmpfs, volatile)

| Path   | sizeLimit | Content                                                             |
| ------ | --------- | ------------------------------------------------------------------- |
| `/tmp` | 16Mi      | Temp files. Mounted by the chart default, no explicit mounts needed |
