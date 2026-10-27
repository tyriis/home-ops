# VictoriaMetrics utility ingestion (central store)

Utility runs a native `VMAgent` that ships every utility platform and app target to the central
`VMSingle` on this cluster, tagged `cluster="utility"`. The write path is in-cluster — agent →
`vmauth` → `VMSingle` — so nothing here depends on `metrics.techtales.io`.

Utility's kube-prometheus-stack (chart 92.14.0) stays enabled and authoritative: its Prometheus
keeps scraping through the chart's `ServiceMonitor`s, keeps its 14d TSDB, evaluates its
`PrometheusRule`s and pages through its Alertmanager. Every target is scraped twice, and utility's
series now exist a second time in the central store.

The operator's Prometheus converter is off here too
(`operator.disable_prometheus_converter: true`), so a `ServiceMonitor` is inert for the VM path:
each target needs a native `VM*Scrape` object. Those twins are the bulk of this change.

- agent `app/vmagent.yaml`; store `app/vmsingle.yaml` — 30d, 50Gi `local-nvme`, shared with main
- platform scrapes `app/scrapes/`; front door `kubernetes/utility/apps/observability/victoria-auth/`
- main cluster side: `kubernetes/main/apps/observability/victoria-metrics/README.md`

## Architecture

```text
utility  VM*Scrape ─▶ VMAgent ──HTTP──▶ vmauth :8427 ─▶ VMSingle :8428
main     VM*Scrape ─▶ VMAgent ──WAN───▶ (same vmauth and store)
utility  Prometheus ─▶ 14d TSDB ─▶ Alertmanager ─▶ Telegram / Grafana OnCall
```

Agent settings: `replicaCount: 1`, `selectAllByDefault: true`, `scrapeInterval: 1m`,
`scrapeTimeout: 30s`, `externalLabels.cluster: utility`, requests `100m` / `256Mi`, no
`statefulMode`.

## Write path and token

- **`/api/v1/write`, no `/insert/` prefix.** A single-node `VMSingle` serves `/api/v1/write`;
  `/insert/*` is cluster-mode `vminsert` only. The `utility-metrics` vmauth user allows exactly
  `/api/v1/write` and denies the rest with `403`, so a wrong path fails loudly.
- **In-cluster vmauth, not the public hostname.** The store is local, so the agent calls
  `vmauth.observability.svc.cluster.local:8427` directly — same user and token as a public write,
  one hop fewer.
- **One copy of the token.** `ExternalSecret/vmagent-remote-write` extracts
  `VMAUTH_TOKEN_UTILITY_METRICS` from `infra/kubernetes/utility/observability/victoria-auth`, the
  authoritative path `vmauth-tokens` already reads, and renders Secret `vmagent-remote-write` key
  `token`. Rotating that key changes both sides — it is the same value `vmauth` reads into its
  environment, so `vmauth` needs its reloader restart to accept the new token.
- **NetworkPolicy.** vmauth admits same-namespace pods labelled `app.kubernetes.io/name: vmagent`
  on TCP 8427. That label sits on the operator-created pod, not in these manifests; dropping it
  stops every write.

## Coverage — platform

10 files in `app/scrapes/`, 12 objects. Job names are taken from utility's live Prometheus scrape
config, so queries selecting a job keep working against `cluster="utility"`.

| Job                                  | Object                                          | Kind              | Target                                                        |
| ------------------------------------ | ----------------------------------------------- | ----------------- | ------------------------------------------------------------- |
| `apiserver`                          | `kube-apiserver`                                | `VMServiceScrape` | `component=apiserver` Service in `default`, https, SA bearer  |
| `kubelet`                            | `kubelet`, `kubelet-cadvisor`, `kubelet-probes` | `VMNodeScrape`    | node 10250, `kubernetes.io/os=linux`, three paths, job forced |
| `kube-etcd`                          | `kube-etcd`                                     | `VMStaticScrape`  | `192.168.100.30:2381`, http, SA bearer                        |
| `kube-scheduler`                     | `kube-scheduler`                                | `VMStaticScrape`  | `192.168.100.30:10259`, https, `insecureSkipVerify`           |
| `kube-controller-manager`            | `kube-controller-manager`                       | `VMStaticScrape`  | `192.168.100.30:10257`, https, `insecureSkipVerify`           |
| `coredns`                            | `coredns`                                       | `VMServiceScrape` | `kube-system`, chart Service, `http-metrics`                  |
| `kube-state-metrics`                 | `kube-state-metrics`                            | `VMServiceScrape` | `observability`, `honorLabels`, two ports                     |
| `node-exporter`                      | `node-exporter`                                 | `VMServiceScrape` | `observability`, `http-metrics`                               |
| `kube-prometheus-stack-alertmanager` | `kube-prometheus-stack-alertmanager`            | `VMServiceScrape` | `http-web` + `reloader-web`, job forced                       |
| `kube-prometheus-stack-operator`     | `kube-prometheus-stack-operator`                | `VMServiceScrape` | https, `insecureSkipVerify`, no bearer, job forced            |

The three static targets use the control-plane VIP `192.168.100.30`; util01 is at
`192.168.100.31` and kubelet is scraped per node, not by address.

## Coverage — app-owned

18 objects beside the app that owns the target, in that app's manifest directory.

| Job                                        | Kind              | App dir                                     |
| ------------------------------------------ | ----------------- | ------------------------------------------- |
| `snapshot-controller`                      | `VMServiceScrape` | `backup-system/snapshot-controller/app`     |
| `volsync-metrics`                          | `VMServiceScrape` | `backup-system/volsync/app`                 |
| `cainjector`, `cert-manager`, `webhook`    | `VMServiceScrape` | `cert-manager/cert-manager/app`             |
| `echo-server`                              | `VMServiceScrape` | `default/echo-server/app`                   |
| `flux-operator`                            | `VMServiceScrape` | `flux-system/flux-operator/app`             |
| `descheduler`                              | `VMServiceScrape` | `kube-tools/descheduler/app`                |
| `cilium-agent`, `cilium-operator`          | `VMServiceScrape` | `kube-system/cilium/app`                    |
| `metrics-server`                           | `VMServiceScrape` | `kube-system/metrics-server/app`            |
| `external-dns-cloudflare`                  | `VMServiceScrape` | `networking/external-dns/cloudflare`        |
| `external-dns-unifi`                       | `VMServiceScrape` | `networking/external-dns/unifi`             |
| `pocket-id`                                | `VMServiceScrape` | `secops/pocket-id/app`                      |
| `tuppr-metrics-service`                    | `VMServiceScrape` | `system-upgrade/tuppr/app`                  |
| `cnpg-system/cnpg-operator-cloudnative-pg` | `VMPodScrape`     | `cnpg-system/cnpg/operator`                 |
| `git-system/forgejo-db`                    | `VMPodScrape`     | `git-system/forgejo/database`               |
| `smartctl-exporter`                        | `VMServiceScrape` | `observability/smartctl-exporter/app`       |
| `vmalert`                                  | `VMServiceScrape` | `observability/vmalert/app`                 |
| `observability/victoria-logs-collector`    | `VMPodScrape`     | `observability/victoria-logs-collector/app` |

`metadata.name` is the default job label; the rows that list several jobs take theirs from a service
label or from a forced `action: replace` on `job`. Intervals: `10s` for `cilium-*` and
`kubelet-cadvisor`, `30s` for `volsync`, `tuppr`, `cert-manager`, `flux-operator` and
`smartctl-exporter`, `1m` otherwise.

## Gaps (dual run)

- **Utility's Prometheus stays the source of truth.** Nothing was switched off: its server,
  `ServiceMonitor`s, `PrometheusRule`s and Alertmanager still run and still page. The central store
  holds a second copy of the same series.
- **No `VMRule` on utility yet.** Its `PrometheusRule`s are not converted, so `cluster="utility"`
  has series but no utility alerts; paging never left Prometheus.
- **`kube-prometheus-stack-prometheus` is not mirrored**, as on main: `vmagent` does not scrape the
  Prometheus server's own `/metrics`, so the chart's self-monitoring rules have no VM input series.
  No `ServiceMonitor`, `PodMonitor` or `PrometheusRule` was added or removed for the VM path.
- **Series population roughly doubles** in the central store. Watch `vm_free_disk_space_bytes`
  against the 30d / 50Gi `local-nvme` budget; a main-only estimate no longer applies.

## Acceptance

```sh
T=$(kubectl --context readonly@utility -n observability get secret vmauth-tokens \
      -o "jsonpath={.data.VMAUTH_TOKEN_GRAFANA_METRICS}" | base64 -d)
for q in 'count by (cluster) (up)' \
        'up{cluster="utility",job="node-exporter"}' \
        'up{cluster="utility",job="kubelet"}' \
        'up{cluster="utility",job="apiserver"}'; do
  curl -s -G -H "Authorization: Bearer $T" --data-urlencode "query=$q" \
    'https://metrics.techtales.io/prometheus/api/v1/query' | head -c 200; echo
done
```

`count by (cluster) (up)` must return both `main` and `utility`, and the three `up` queries must be
non-empty. No `utility` at all means the agent is not writing — neither agent nor vmauth is scraped
into the store, so read the `vmagent` pod logs for remote-write errors and check the vmauth
NetworkPolicy. One empty job means that object's selector or port name matches nothing.

## Operational notes

- **No persistent queue, on purpose.** The target is in-cluster on a single-node cluster, so a PVC
  buys no availability it does not already lack. A `vmauth` or `VMSingle` restart drops buffered
  samples — main, which writes over the WAN, runs `statefulMode: true` instead.
- **Adding a target**: put `vm-service-scrape.yaml` (or `vm-pod-scrape.yaml`) next to the
  `ServiceMonitor` it mirrors, list it in that app's `kustomization.yaml`, then verify
  `up{job="<name>", cluster="utility"}`. `selectAllByDefault: true` needs no value change and no
  agent restart.
- **Store capacity** is a `VMSingle` change (retention or PVC), not an agent change.

## Follow-ups

- Convert utility's `PrometheusRule`s to `VMRule`s, give `VMAlert` a notifier, then retire utility's
  Prometheus and its `ServiceMonitor`s — main's run 2 order, as a separate cutover.
- Decide whether the in-cluster `vmauth` hop stays: one proxy, in exchange for the token allowlist
  and one write-URL shape for both clusters.
