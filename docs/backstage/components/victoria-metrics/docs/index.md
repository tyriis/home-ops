# VictoriaMetrics

One `VMSingle` in `observability` on the utility cluster holds the metrics of both clusters. It sits
behind `vmauth` at [https://metrics.techtales.io](https://metrics.techtales.io), keeps 30d of data
on a 50Gi `local-nvme` volume, and runs in dual run beside the Prometheus of each cluster.

Agents write; every other client reads through `vmauth`.

## Writers

- **main** — headless `VMAgent`, `statefulMode: true` on a 5Gi `ceph-block` PVC, so a WAN gap or a
  store restart is buffered instead of dropped. Writes to `https://metrics.techtales.io/api/v1/write`.
  Source: [`kubernetes/main/apps/observability/victoria-metrics/app/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/main/apps/observability/victoria-metrics/app)
- **utility** — stateless `VMAgent`, no queue: the store is local, so buffering buys nothing. Writes
  to `vmauth.observability.svc.cluster.local:8427` with its own `utility-metrics` token.
  Source: [`kubernetes/utility/apps/observability/victoria-metrics/app/`](https://github.com/tyriis/home-ops/tree/main/kubernetes/utility/apps/observability/victoria-metrics/app)

Both agents run `selectAllByDefault: true`; the default scrape interval is `1m`, with per-object
overrides (`10s` for `cilium-*` and the kubelet cadvisor scrape, `30s` for `volsync` and `tuppr`).

## The `cluster` label

Every sample carries `cluster=main` or `cluster=utility`, taken from the agent's
`externalLabels.cluster`. Both agents set `overrideHonorLabels: true`: a target that exports its own
`cluster` label cannot replace the external one, and its value is kept as `exported_cluster`
instead. Without it, one exporter's label moves its whole series set into the other cluster's
namespace without any scrape failing.

The rule is set on the agents and not in the charts because Prometheus keeps its own `honorLabels`
handling on both clusters. The pinned label is therefore a property of the VM write path, not of the
scrape objects.

## Verify

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-tokens \
      -o "jsonpath={.data.VMAUTH_TOKEN_GRAFANA_METRICS}" | base64 -d)
curl -s -G -H "Authorization: Bearer $T" --data-urlencode 'query=count by (cluster) (up)' \
  'https://metrics.techtales.io/prometheus/api/v1/query'
```

Both `main` and `utility` must be present. A missing cluster means that agent is not writing; a
missing job inside a cluster means a scrape object selects nothing.

## Dual run

Prometheus on both clusters is still the source of truth for its own rules: it keeps its TSDB,
evaluates its `PrometheusRule`s and pages through its Alertmanager. Utility's `PrometheusRule`s are
not converted to `VMRule`s yet, so `cluster="utility"` has series but no alerts of its own.
