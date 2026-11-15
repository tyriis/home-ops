# Disk Health and SMART Self-Tests

## Drives

Both bays carry identical-vintage spinners (verified 2026-11-15):

| Bay | Device Model                 | Serial   | Capacity | POH at 2026-11-15 |
| --- | ---------------------------- | -------- | -------- | ----------------- |
| sda | Seagate IronWolf ST4000VN008 | ZGY18C52 | 4 TB     | 76,394 h          |
| sdb | Seagate IronWolf ST4000VN008 | ZDH2RGZG | 4 TB     | 76,385 h          |

Arrays: `md0` (boot), `md1` (system), `md2` (data) — all `raid1 [2/2] [UU]`.
Per-disk health records live in the disk inventory (`home-ops-inventory` repo:
`seagate-ironwolf-st4000vn008-zgy18c52`, `seagate-ironwolf-st4000vn008-zdh2rgzg`).

## Health verdicts (2026-11-15)

- **sda `ZGY18C52` — HEALTHY.** Every defect counter zero (5/187/197/198/199), error
  log empty (proven host-side), ~159 TBW, lifetime max temp 32 °C. Only risk is age.
- **sdb `ZDH2RGZG` — WATCH.** 16 reallocated / 15 reported-uncorrect — but all 15
  error-log records date to POH 4,855–4,856, the disk's first ~202 days. Static for
  ~8.2 years. Acceptable as one side of a RAID1; not a sole-drive target.
- **Pair plan:** same batch, 76.4k h each — replace both proactively, not reactively.

## Monitoring notes

- The smartctl-exporter keeps warning on sdb (`exit_status = 64`, ~30 WARN/h)
  because the old records sit in the log — this fires once per scrape and is
  **not** new damage. The newness check is that
  `smartctl_device_error_log_count{host="synology"}` stays flat at 15, and it has.
- Self-test history on **both** bays stopped at ~48.7k POH — the old DSM
  scheduler had been dead ~3.2 years; replaced as below.

## SMART self-test schedule

Until 2026-11-15 the last recorded self-test on either bay dated to ~48.7k h
(~3.2 years stale) — the DSM scheduler had died. A replacement task was
configured directly in DSM (Storage Manager → Smart Test → Create):

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

| What                     | Probe                                                          | Expected                                                                                      |
| ------------------------ | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Self-test cadence (host) | `sudo smartctl -l selftest /dev/sda`                           | a fresh `Short offline — Completed without error` row per day, `LifeTime` advancing ~24 h/day |
| Drive identity (host)    | `sudo smartctl -i /dev/sda`                                    | serial still `ZGY18C52` — device letters drift, serials don't                                 |
| Error-log newness        | central VM: `smartctl_device_error_log_count{host="synology"}` | sdb stays 15, sda 0                                                                           |
| Array state (host)       | `cat /proc/mdstat`                                             | all arrays `[2/2] [UU]`                                                                       |
| Kernel I/O errors (host) | `dmesg \| grep -iE 'ata[0-9]\|sdb\|blk\|I/O error' \| tail`    | empty                                                                                         |
