# Storage

No app data writes to node disk. Data lives on the Ceph config PVC or in RAM.

## Config PVC (Ceph, persistent)

| Path           | Content                             |
| -------------- | ----------------------------------- |
| `recyclarr.db` | History and state of past sync runs |

The settings file `recyclarr.yml` comes from a ConfigMap and mounts read-only at
`/config/recyclarr.yml`.

VolSync replicates the PVC to MinIO (`backup-system`).

## RAM (tmpfs, volatile)

| Path           | sizeLimit | Content                                  |
| -------------- | --------- | ---------------------------------------- |
| `/config/logs` | 16Mi      | Run logs. Lost with the pod              |
| `/tmp`         | 16Mi      | Temp files. Mounted by the chart default |
