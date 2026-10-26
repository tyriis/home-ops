# Storage

No app data writes to node disk. Data lives on the Ceph config PVC or in RAM.

## Config PVC (Ceph, persistent)

| Path       | Content                        |
| ---------- | ------------------------------ |
| `db/`      | Main database                  |
| `config/`  | Settings, contains the API key |
| `cache/`   | Subtitle search cache          |
| `backup/`  | App backups                    |
| `restore/` | Temp area for restore uploads  |

VolSync replicates the PVC to MinIO (`backup-system`).

## RAM (tmpfs, volatile)

| Path          | sizeLimit | Content                   |
| ------------- | --------- | ------------------------- |
| `/config/log` | 48Mi      | See [Logging](logging.md) |
| `/tmp`        | 16Mi      | Temp files                |
