# Logging

Sonarr writes logs to two destinations.

| Destination          | Content                         | Retention                                 |
| -------------------- | ------------------------------- | ----------------------------------------- |
| `/config/logs/*.txt` | Full app logs                   | tmpfs volume, 48Mi max, lost with the pod |
| stdout               | Console log, scraped by vlagent | 30d in VictoriaLogs                       |

## File rotation

The app writes three files: `sonarr.txt` (info), `sonarr.debug.txt` (disabled),
`sonarr.trace.txt` (disabled). Debug and trace get lines only when you enable them in the UI.

These environment variables control the rotation:

```yaml
SONARR__LOG__ROTATE: 10 # number of archive files per stream
SONARR__LOG__SIZELIMIT: 1 # MiB per file, upstream limit is 10
```

The maximum size is 3 streams x 11 files x 1MiB = 34.6MiB. You must keep the `sizeLimit`
of the `logs` volume above this value (48Mi).

## Data exposure

File logs contain media titles and paths. They exist in RAM only.
stdout goes to VictoriaLogs and contains media titles.
