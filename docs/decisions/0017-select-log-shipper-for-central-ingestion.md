---
status: proposed
date: 2026-10-13
decision-makers: [tyriis]
---

# Use victoria-logs-collector (vlagent) as the central log shipper

## Context and Problem Statement

Phase 1 of central log ingestion is live: VictoriaLogs runs on utility, behind vmauth at
`logs.techtales.io`, with per-unit tokens (ADR 0016). No log shipper is deployed on any unit yet.
We need one shipper for both clusters (issue tyriis/home-ops#10975, follow-up #10985).

Hard requirement from #10975: every producer must send a non-form content type (for example
`application/json`). A form-encoded body is silently dropped (200 response, zero rows ingested).

## Decision Drivers

- Throughput and CPU/memory footprint on small nodes (utility is 1 node).
- Native fit with VictoriaLogs and vmauth per-unit tokens.
- Simple Helm deployment via Flux.
- Community adoption as a homelab baseline.

## Considered Options

- **victoria-logs-collector (vlagent)** — chosen
- Fluent Bit (community precedent: 37 repos on kubesearch.dev)
- Vector (native `victorialogs_high_output` sink)
- Promtail, repointed to VictoriaLogs via the Loki push API (needs a vmauth `url_maps` change)

## Decision Outcome

Chosen option: **victoria-logs-collector (vlagent)**, deployed as a Flux HelmRelease on the utility
and main clusters, shipping to VictoriaLogs through vmauth with a per-cluster unit token.

Evidence:

- Community: 57 repos on kubesearch.dev, the most of any log shipper (fluent-bit 37, promtail 12
  on the ghcr path plus 21 on a grafana-operator path, Vector and Alloy 0 found under the paths
  tried).
- Benchmark (VictoriaMetrics, 2026; vendor-run, 1 CPU / 1 GiB limit, default configs, 100 pods):

  | Collector  | Peak logs/s | CPU @ 10k logs/s | Memory @ 10k logs/s |
  | ---------- | ----------- | ---------------- | ------------------- |
  | vlagent    | 143,000     | 0.062 cores      | 27.9 MiB            |
  | Fluent Bit | 31,300      | 0.260 cores      | 78.1 MiB            |
  | Vector     | 25,000      | 0.412 cores      | 153.5 MiB           |
  | Promtail   | 13,400      | 0.655 cores      | 63.0 MiB            |

  Fluent Bit and Vector produced split records during file rotation in the benchmark.

Accepted limits: vlagent has no multiline joining and no custom parsers. Where those are needed,
keep the existing collector or add a second one.

## Consequences

Positive:

- Lowest footprint of the tested shippers, which suits utility.
- Automatic JSON and Kubernetes system log parsing, no extra config.
- Disk buffering when the backend is down (meets ADR 0016 R6).

Negative / accepted risks:

- Vendor benchmark: numbers are indicative until reproduced (`github.com/VictoriaMetrics/log-collectors-benchmark`).
- No multiline or custom parsing; a second shipper is needed for those cases.

## More Information

- Related: ADR 0016 (central log platform), issue tyriis/home-ops#10975 (shipper selection),
  issue tyriis/home-ops#10985 (deploy on utility and main).
- ADR 0016 flips to `accepted` once the first shipper delivers real logs (#10975 acceptance criteria).
