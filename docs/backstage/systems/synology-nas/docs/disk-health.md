# Disk Health and SMART Self-Tests

## Drives

Both bays carry identical-vintage spinners (verified 2026-11-15):

| Bay | Device Model                 | Serial                               | Capacity | POH at 2026-11-15 |
| --- | ---------------------------- | ------------------------------------ | -------- | ----------------- |
| sda | Seagate IronWolf ST4000VN008 | (verify with `smartctl -i /dev/sda`) | 4 TB     | 76,393 h          |
| sdb | Seagate IronWolf ST4000VN008 | ZDH2RGZG                             | 4 TB     | 76,385 h          |

Arrays: `md0` (boot), `md1` (system), `md2` (data) — all `raid1 [2/2] [UU]`.

## Health state (verified 2026-11-15)

- **sdb error log is ancient and static.** All 15 ATA error-log records
  occurred at power-on lifetime 4,855–4,856 h — the disk's first ~202 days.
  Zero new records in ~8.2 years since. Reallocated_Sector_Ct 16,
  Reported_Uncorrect 15, Current_Pending_Sector 0, UDMA_CRC 0 — all frozen
  since early life. `dmesg` and `/var/log/messages`: no I/O errors.
- **Monitoring caveat:** the smartctl-exporter keeps warning
  (`exit_status = 64`, ~30 WARN/h) because the old records sit in the log —
  this fires once per scrape and is not new damage. The newness check is
  that `smartctl_device_error_log_count` stays flat, and it has.
- **sda:** clean — zero reallocated, zero error-log records.
- **Verdict:** both drives WATCH on age alone (76.4k h, same batch).
  No degradation. Plan a proactive pair replacement for the offsite volume
  on schedule, not under pressure.

## SMART self-test schedule

A long gap existed until 2026-11-15: the last recorded self-test on sdb
dated to 48,732 h (~3.2 years stale) — the DSM scheduler had died.

A replacement task was configured directly in DSM
(Storage Manager → Health Management → SMART Test → Create):

| Setting               | Value                          |
| --------------------- | ------------------------------ |
| Task name             | `disk-test`                    |
| Task type             | All tasks (SMART test)         |
| S.M.A.R.T. Test Type  | Quick Test                     |
| S.M.A.R.T. Test Range | Test all supported drives      |
| IronWolf Health Test  | Test all supported drives      |
| Schedule              | Run on the following days: Mon |
| First run time        | 04:00                          |
| Frequency             | Every day                      |
| Last run time         | 04:00                          |

Note: DSM stores this task in the host, not in this repository — the repo
is the only system of record for it. If the NAS is rebuilt, recreate it.

## Verify live state

| What                     | Probe                                                          | Expected                                                                                     |      |      |              |       |       |
| ------------------------ | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------- | ---- | ---- | ------------ | ----- | ----- |
| Self-test cadence (host) | `sudo smartctl -l selftest /dev/sdb`                           | a fresh `Short offline  Completed without error` row per day, `LifeTime` advancing ~24 h/day |      |      |              |       |       |
| Drive identity (host)    | `sudo smartctl -i /dev/sda`                                    | Model Family: Seagate IronWolf — record sda serial here                                      |      |      |              |       |       |
| Error-log newness        | central VM: `smartctl_device_error_log_count{host="synology"}` | sdb stays 15, sda 0                                                                          |      |      |              |       |       |
| Array state (host)       | `cat /proc/mdstat`                                             | all arrays `[2/2] [UU]`                                                                      |      |      |              |       |       |
| Kernel I/O errors (host) | `dmesg \                                                       | grep -iE 'ata[0-9]\                                                                          | sdb\ | blk\ | I/O error' \ | tail` | empty |
