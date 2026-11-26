# Storage

App data lives on the Ceph config PVC, the NAS, or RAM. Transcode cache is the one node-disk consumer.

## Config PVC (Ceph, persistent)

| Path                                  | Content                                             |
| ------------------------------------- | --------------------------------------------------- |
| `Library/Application Support/`        | Database, metadata, and the app support dir         |
| `…/Plex Media Server/Preferences.xml` | Server preferences, incl. `TranscoderTempDirectory` |
| `…/Cache/Transcode/`                  | Background transcode and Media Optimizer output     |

VolSync replicates the PVC to MinIO (`backup-system`).

## Transcode cache (node disk, volatile)

The image entrypoint forces the preference `TranscoderTempDirectory=/transcode` on first run.
A 100Gi disk-backed emptyDir is mounted there for live session files.

## Media (NFS)

The NAS share `nas.techtales.io:/mnt/tank/media` is mounted read-only at `/media`.

## RAM (tmpfs, volatile)

| Path                       | sizeLimit | Content                                                         |
| -------------------------- | --------- | --------------------------------------------------------------- |
| `/tmp`                     | 16Mi      | Plex scratch dirs (`pms-<uuid>/`), mounted by the chart default |
| `…/Plex Media Server/Logs` | 32Mi      | Plex log files. Plex rotates and deletes old files itself.      |
