# Storage

No app data writes to node disk. Data lives on the Ceph config PVC or in RAM.

## Config PVC (Ceph, persistent)

| Path           | Content                                                      |
| -------------- | ------------------------------------------------------------ |
| `prowlarr.db`  | Main database. Contains the API keys of all managed indexers |
| `config.xml`   | Boot config, made from environment variables                 |
| `asp/`         | ASP.NET DataProtection keys                                  |
| `Definitions/` | Indexer definition cache                                     |
| `Backups/`     | App backups, 1 every 7 days, 28 days retention               |

VolSync replicates the PVC to MinIO (`backup-system`). The PVC is ReadWriteOnce:
scale the deployment to 0 before you mount it somewhere else.

Do not mount a volume over `asp/`. If you do, all sessions become invalid on every
pod restart.

## RAM (tmpfs, volatile)

| Path             | sizeLimit | Content                         |
| ---------------- | --------- | ------------------------------- |
| `/config/logs`   | 48Mi      | See [Logging](logging.md)       |
| `/tmp`           | 16Mi      | Temp files                      |
| `/config/Sentry` | 8Mi       | Sentry outbox. Analytics is off |
