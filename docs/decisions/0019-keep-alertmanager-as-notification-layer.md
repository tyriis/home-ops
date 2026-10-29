---
status: proposed
date: 2026-10-18
decision-makers: [tyriis]
---

# Keep Alertmanager as the sole notification layer for both clusters

## Context and Problem Statement

Both clusters run a Prometheus-operator-style stack, and the public alerting entry points are
the two no-auth Alertmanager instances (`alertmanager.techtales.io` on main,
`alertmanager…utility.techtales.io` on utility). Because metrics already moved to
VictoriaMetrics, the question was raised whether the alerting path can drop Alertmanager and
"live in the Victoria ecosystem" end to end.

The Victoria docs give a precise answer: `vmalert` is a rule evaluator only. It queries a
datasource (`-datasource.url` — VictoriaMetrics, VictoriaLogs, Prometheus-compatible) and POSTS
firing/resolved groups to `-notifier.url`, which speaks the Alertmanager v0.16+ API. It has no
native Slack/Telegram/email senders, no routing tree, no grouping, inhibition or silences. So a
"Victoria-only" alerting stack is really VictoriaMetrics + VictoriaLogs + vmalert +
**Alertmanager** — the same prometheus/alertmanager binary, just fed by vmalert instead of
Prometheus.

"Alertmanager-free" therefore means _replacing_ it, not removing it:

- Grafana unified alerting as the notifier — available on **main only**; utility has no
  Grafana, and its public Alertmanager is the sole notifier there.
- A self-written webhook shim (n8n flow or a small HTTP receiver) that consumes the
  Alertmanager webhook format vmalert emits and posts to Telegram. The shim is still a
  notification layer, now self-maintained.

The decision to record: keep Alertmanager as the single notification layer on both clusters, and
treat rule evaluation (Prometheus rules today, vmalert later) as a separate, swappable concern.

## Decision Drivers

- Every alert path in either ecosystem terminates at an Alertmanager or an
  AM-compatible receiver — there is no "no notifier" option.
- Alertmanager is cheap to keep: stateless, one config file, ~20 MB RSS.
- One notifier for both clusters keeps the public endpoints, the Telegram route and the
  Grafana OnCall integration stable.
- Rule evaluation should still be able to move to vmalert (and to VictoriaLogs LogsQL
  rules) later, without touching notification config.

## Considered Options

- **A. Keep Alertmanager as notifier, keep Prometheus rule evaluation** (status quo).
- **B. Keep Alertmanager as notifier, move rule evaluation to vmalert** — same delivery, the
  evaluator survives a single-node Prometheus outage, and LogsQL alerts plug into the same
  `-notifier.url`.
- **C. Remove Alertmanager; notify via Grafana contact points** — rejected: utility has no
  Grafana, so it would lose its only notifier, and main gains a Grafana dependency on the
  alert path.
- **D. Remove Alertmanager; self-written webhook shim** — rejected: rebuilds grouping,
  silences and inhibition by hand for no operational gain.

## Decision Outcome

Chosen option: **A now, B as the target.** Alertmanager stays the only notification layer on
both clusters, unchanged. Rule evaluation may move to vmalert on both clusters at a later
iteration; when it does, only each PrometheusRule source and vmalert's `-datasource.url` change
— Alertmanager config, routes and receivers are not touched.

Acceptance criteria for a later vmalert migration:

- vmalert runs on each cluster with `-datasource.url` pointed at that cluster's
  VictoriaMetrics and `-notifier.url` at the existing in-cluster Alertmanager.
- A test alert fires end to end to Telegram from each cluster before any Prometheus rule
  group is disabled.
- Prometheus rule evaluation is removed only after 7 days with both evaluators quiet or
  equivalent.

## Consequences

- Good, because the notification layer does not change — existing routes to Telegram and
  Grafana OnCall keep working with no migration.
- Good, because evaluation and delivery are now explicitly decoupled, so a Prometheus → vmalert
  evaluator swap is a small, reversible PR.
- Neutral, because an Alertmanager remains a required component on both clusters — this ADR
  records it as a keeper, not as debt.
- Bad, because option B adds one more moving part (vmalert) when executed; deferred until the
  single-node Prometheus is actually a pain point.

## More Information

- vmalert docs — `-notifier.url` requires Alertmanager v0.16+: docs.victoriametrics.com/victoriametrics/vmalert/
- vmalert + VictoriaLogs alerting: docs.victoriametrics.com/victorialogs/vmalert/
- ADR 0016 (VictoriaMetrics/VictoriaLogs platform on utility), ADR 0018 (Loki retirement)
