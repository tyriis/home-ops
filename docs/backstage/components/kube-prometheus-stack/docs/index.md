# kube-prometheus-stack

kube-prometheus-stack (KPS) is the monitoring stack of the main cluster. It runs the Prometheus
operator, Prometheus, Alertmanager, kube-state-metrics, node-exporter, blackbox-exporter, the
control-plane ServiceMonitors, and the bundled default alert-rule set.

Definition:
[`kubernetes/main/apps/observability/kube-prometheus-stack/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/observability/kube-prometheus-stack)
(HelmRelease, chart 92.14.1).

## Local rule overrides

Default rules ship inside the chart. To change one, disable it in the app HelmRelease with
`defaultRules.disabled.<alertName>: true`, then ship the replacement as a plain `PrometheusRule`
in `kubernetes/main/apps/observability/kube-prometheus-stack/observability/`.
prometheus-operator has no replace mechanism: the operator writes every selected
`PrometheusRule` verbatim to the rule files. A rule that merely shares an alert name runs beside
the chart default and alerts twice. Disabling via values is what makes the swap single-source.
Values-only tweaks are also native: `customRules.<alertName>.for` and
`customRules.<alertName>.severity` retune a chart rule without replacing it.

### etcdDatabaseHighFragmentationRatio

The chart default fires when the etcd database in-use size falls below 50% of the allocated file
size, with a 10m `for`. This is wrong for this homelab control plane:

- The etcd database is small and settled: about 0.35 GiB allocated, 0.14 GiB in use.
- An etcd file never shrinks by itself. Compaction frees pages inside the file, the file keeps
  its size, so the ratio drifts below 0.5 as a normal end state.
- With only a 10m `for` and the ratio jittering across 0.50, the alert flapped on and off for
  days.

The override keeps the ratio check and adds a materiality floor: the fragmented part of the file
must exceed 2 GiB, held for 1h. Small-database drift can never fire it. A large database with
gigabytes of waste still pages, because that waste slows fsync and defrag.

The VictoriaMetrics side evaluates the same logic. `rules/kps/` holds vendored chart copies that
vmalert renders, so the twin in
`victoria-metrics/app/rules/kps/kube-prometheus-stack-etcd.yaml` carries the change in place,
marked `LOCAL OVERRIDE (re-apply on re-render)`.

## Runbook: reclaim fragmented etcd space

The rule change stops the alert noise. Defragmentation reclaims the space. Talos runs etcdctl
natively via `talosctl etcd`, so no shell access to the etcd member is necessary. Run one node at
a time. Defrag blocks reads and writes on that member briefly while it rebuilds. Followers first,
leader last.

1. Show DB size, in-use percentage and leader per member:
   `talosctl -n 192.168.100.101,192.168.100.102,192.168.100.103 etcd status`
2. Defragment one follower: `talosctl -n <follower-ip> etcd defrag`
3. Repeat for the second follower, then the leader (the LEADER column names it).
4. Re-run step 1 — the DB SIZE column should closely match the IN USE column
   (in-use ratio back to ~100% per member).
