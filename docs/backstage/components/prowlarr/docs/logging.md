# Logging

Prowlarr writes logs to two destinations.

| Destination          | Content                         | Retention                                |
| -------------------- | ------------------------------- | ---------------------------------------- |
| `/config/logs/*.txt` | Full app logs                   | tmpfs volume, 8Mi max, lost with the pod |
| stdout               | Console log, scraped by vlagent | 30d in VictoriaLogs                      |

## File rotation

The app writes three files: `prowlarr.txt` (info), `prowlarr.debug.txt` (disabled),
`prowlarr.trace.txt` (disabled). Debug and trace get lines only when you enable them in the UI.

These environment variables control the rotation:

```yaml
PROWLARR__LOG__ROTATE: 1 # number of archive files per stream. Default is 50
PROWLARR__LOG__SIZELIMIT: 1 # MiB per file, upstream limit is 10
```

The maximum size is 3 streams x 2 files x 1MiB = 6.3MiB. You must keep the `sizeLimit`
of the `logs` volume above this value (8Mi).

## Data exposure

Log lines name indexers, not media.
stdout goes to VictoriaLogs.
