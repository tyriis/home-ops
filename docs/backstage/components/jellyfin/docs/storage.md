# Storage

No app data writes to node disk. Data lives on the Ceph config PVC, the NAS, or in RAM.

## Config PVC (Ceph, persistent)

| Path    | Content                          |
| ------- | -------------------------------- |
| `data/` | Database, metadata, and settings |

VolSync replicates the PVC to MinIO (`backup-system`).

## Media (NFS)

The NAS share `nas.techtales.io:/mnt/tank/media` is mounted read-only at `/media`.

## RAM (tmpfs, volatile)

| Path          | sizeLimit | Content                                  |
| ------------- | --------- | ---------------------------------------- |
| `/config/log` | 32Mi      | App logs. Lost with the pod              |
| `/tmp`        | 16Mi      | Temp files. Mounted by the chart default |
| `/cache`      | 2500Mi    | Transcode cache. 2GiB free required.     |
