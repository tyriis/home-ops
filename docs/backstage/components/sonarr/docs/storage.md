# Storage

No app data writes to node disk. Data lives on the Ceph config PVC or in RAM.

## Config PVC (Ceph, persistent)

| Path          | Content                                        |
| ------------- | ---------------------------------------------- |
| `sonarr.db`   | Main database. Config values live here too     |
| `config.xml`  | Boot config, made from environment variables   |
| `asp/`        | ASP.NET DataProtection keys                    |
| `MediaCover/` | Poster and fanart cache                        |
| `Backups/`    | App backups, 1 every 7 days, 28 days retention |

VolSync replicates the PVC to MinIO (`backup-system`).

Do not mount a volume over `asp/`. If you do, all sessions become invalid on every
pod restart.

## RAM (tmpfs, volatile)

| Path             | sizeLimit | Content                         |
| ---------------- | --------- | ------------------------------- |
| `/config/logs`   | 48Mi      | See [Logging](logging.md)       |
| `/tmp`           | 16Mi      | Temp files                      |
| `/config/Sentry` | 8Mi       | Sentry outbox. Analytics is off |
