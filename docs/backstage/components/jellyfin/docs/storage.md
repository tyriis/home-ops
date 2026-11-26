# Storage

App data lives on the Ceph config PVC, the NAS, or RAM. Transcode cache is the one node-disk consumer.

## Config PVC (Ceph, persistent)

| Path    | Content                          |
| ------- | -------------------------------- |
| `data/` | Database, metadata, and settings |

VolSync replicates the PVC to MinIO (`backup-system`).

## Media (NFS)

The NAS share `nas.techtales.io:/mnt/tank/media` is mounted read-only at `/media`.

## Node disk (ephemeral, volatile)

| Path     | sizeLimit | Content         |
| -------- | --------- | --------------- |
| `/cache` | 100Gi     | Transcode cache |

## RAM (tmpfs, volatile)

| Path          | sizeLimit | Content                                  |
| ------------- | --------- | ---------------------------------------- |
| `/config/log` | 32Mi      | App logs. Lost with the pod              |
| `/tmp`        | 16Mi      | Temp files. Mounted by the chart default |
