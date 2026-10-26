# Logging

Bazarr writes logs to two destinations.

| Destination              | Content                            | Retention                                 |
| ------------------------ | ---------------------------------- | ----------------------------------------- |
| `/config/log/bazarr.log` | Full app logs                      | tmpfs volume, 48Mi max, lost with the pod |
| stdout                   | Same log lines, scraped by vlagent | 30d in VictoriaLogs                       |

## File rotation

The app keeps 1 file per day, and keeps 7 days. Upstream has no size control. The 48Mi
`sizeLimit` of the tmpfs volume is the only limit. Measured use is under 1MiB per day.

File logs and stdout share one log level (`DYNACONF_general__logs`). You cannot set a
separate console level. To remove detail from stdout, raise the level and accept less
detail in the file log too.

## Data exposure

Log lines can contain media titles and paths.
stdout goes to VictoriaLogs.
