---
status: proposed
date: 2026-10-13
decision-makers: [tyriis]
---

# Deprecate Loki and Promtail in favour of the VictoriaLogs stack

## Context and Problem Statement

Logs are split between Loki (with Promtail on main) and the VictoriaLogs platform
(ADR 0016, issue #10975). Two backends mean two shipper fleets and two query paths in Grafana.
Promtail is deprecated by Grafana. On kubesearch.dev, victoria-logs-collector has the most
repos (57), against Loki 39 and promtail 33 (ADR 0016 sources).

## Decision Drivers

- Small footprint on the 1-node utility cluster (ADR 0016 R4/R7).
- Community popularity and the VictoriaMetrics ecosystem (one vendor for metrics and logs).
- One shipper and one backend to operate.

## Considered Options

- **Keep Loki and Promtail** (status quo): two backends, two shipper fleets.
- **Side-by-side evaluation, then decide** — chosen as the first step.
- **Retire Loki and Promtail now**: no evaluation period.

## Decision Outcome

Chosen option: **side-by-side evaluation of VictoriaLogs (vlagent) against Loki and Promtail
before any retirement.** No cutoff date is set. The retirement decision is made after the
evaluation.

- Shipper under evaluation: victoria-logs-collector (vlagent), per ADR 0017.
- Backend under evaluation: VictoriaLogs single-node behind vmauth, per ADR 0016.
- Grafana: `victoriametrics-logs-datasource` added alongside the Loki datasource.

## Consequences

- Positive: a reversible step; the evaluation produces real data before any removal.
- Negative: two stacks run in parallel for the length of the evaluation.
- The OTLP log path (opencode, OTel spec 2026-08-12) stays on Loki for now. Moving it to
  VictoriaLogs is a later iteration (follow-up ticket).
- Tempo is unaffected.

## More Information

- ADR 0016 (central log platform on VictoriaLogs)
- ADR 0017 (victoria-logs-collector as shipper)
- Issues tyriis/home-ops#10975 and #10985
