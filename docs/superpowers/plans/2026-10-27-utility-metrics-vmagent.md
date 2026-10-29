# Utility metrics ingestion into the central VictoriaMetrics store

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.
> Issue: https://github.com/tyriis/home-ops/issues/11383

**Goal:** A VMAgent on the utility cluster remote-writes every utility platform/app metric to the
central VMSingle (`cluster="utility"`), so `count by (cluster) (up)` returns both `main` and
`utility`.

**Architecture:** Utility runs a native `VMAgent` (`selectAllByDefault: true`,
`externalLabels.cluster: utility`) that writes in-cluster to `vmauth`
(`http://vmauth.observability.svc.cluster.local:8427/api/v1/write`) with the existing
`utility-metrics` vmauth user token. Utility's own Prometheus stays as source of truth (dual run).
Because the operator's Prometheus converter is disabled on both clusters, every target must be
described by a native `VM*Scrape` object, so this change also converts every utility
ServiceMonitor/PodMonitor to a VM twin.

**Spec:** this plan plus the live utility Prometheus scrape config, which is the authority for
selectors, ports, intervals and relabel rules:
`curl -s https://prometheus.utility.techtales.io/api/v1/status/config`

## Global constraints

- Write path is `/api/v1/write` on `vmauth`. There is **no** `/insert/` prefix (that is
  cluster-mode `vminsert` only) and `utility-metrics` allows only `/api/v1/write`.
- `externalLabels.cluster` must be `utility` — never `main`.
- API group: `operator.victoriametrics.com/v1beta1`. No `ServiceMonitor`, `PodMonitor` or
  `PrometheusRule` is created for the VM path; the chart-rendered ones stay for Prometheus.
- Every YAML file starts with `---` and the `# yaml-language-server: $schema=` line, 2-space
  indent, prettier-clean.
- `metadata.name` is the default `job` label. Where the live Prometheus job differs (namespace
  prefixed PodMonitor jobs, cert-manager per-service jobs, service-name jobs such as
  `volsync-metrics`/`tuppr-metrics-service`), fix it with an explicit `action: replace` relabel on
  `job` **and** name the object after the job where a single job is produced.
- Comments: only cross-file constraints (why a job label must stay) — as in
  `kubernetes/main/apps/observability/victoria-metrics/app/scrapes/`.
- No `git` commands in sub-tasks; the coordinator commits.
- Do not touch unrelated working-tree changes, or anything under `kubernetes/main`, `kubernetes/base`,
  `kubernetes/components`.

## Review focus

- Label keys: Prometheus' `__meta_kubernetes_service_label_<x>` mangles `.`, `/` and `-` into `_`.
  Wrong recovery (`self_monitor` vs `self-monitor`) silently selects nothing → every object's
  selectors must match a live Service/Pod.
- Job labels: a renamed job breaks dashboards and rules more quietly than a missing target.
- Intervals: 10s only for `cilium-*` and the kubelet cadvisor scrape; 30s for `volsync`, `tuppr`,
  `cert-manager`, `flux-operator`, `smartctl-exporter`; 1m otherwise.
- TLS/authorization: kubelet/apiserver/etcd/scheduler/controller-manager need
  `bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token`; `metrics-server`,
  `volsync`, `descheduler` are https with `insecureSkipVerify: true`.
- The vmauth NetworkPolicy must admit `app.kubernetes.io/name: vmagent` on 8427 or every write is
  refused.

---

### Task 1: VMAgent, token, network policy (lane A)

**Files:**

- Create: `kubernetes/utility/apps/observability/victoria-metrics/app/vmagent.yaml`
- Create: `kubernetes/utility/apps/observability/victoria-metrics/app/external-secret.yaml`
- Modify: `kubernetes/utility/apps/observability/victoria-metrics/app/kustomization.yaml`
- Modify: `kubernetes/utility/apps/observability/victoria-metrics/flux-sync.yaml`
- Modify: `kubernetes/utility/apps/observability/victoria-auth/app/network-policy.yaml`

**Interfaces:** the Secret name `vmagent-remote-write` with key `token`, and the label
`app.kubernetes.io/name: vmagent` on the operator-created pod, are consumed by Task 2 and by vmauth.

- [ ] `VMAgent/vmagent`: `replicaCount: 1`, `selectAllByDefault: true`, `scrapeInterval: 1m`,
      `scrapeTimeout: 30s`, `externalLabels: {cluster: utility}`,
      `remoteWrite: [{url: http://vmauth.observability.svc.cluster.local:8427/api/v1/write,
bearerTokenSecret: {name: vmagent-remote-write, key: token}}]`,
      `resources.requests: {cpu: 100m, memory: 256Mi}`. No `statefulMode` (target is in-cluster).
- [ ] `ExternalSecret/vmagent-remote-write`: `extract` key
      `infra/kubernetes/utility/observability/victoria-auth`, template
      `token: "{{ .VMAUTH_TOKEN_UTILITY_METRICS }}"` — same authoritative path vmauth reads.
- [ ] vmauth NetworkPolicy: add a third ingress rule, `podSelector` (same namespace) matching
      `app.kubernetes.io/name: vmagent`, port TCP 8427.
- [ ] kustomization gains `./vmagent.yaml` and `./external-secret.yaml` (plus Task 2's `./scrapes/...`).
- [ ] flux-sync gains `dependsOn: victoria-operator` and `dependsOn: victoria-auth` (namespace
      `observability`).

**Verify:** `kustomize build kubernetes/utility/apps/observability/victoria-metrics/app` and
`kubectl --context readonly@utility apply --dry-run=client -f <built output>`, plus the same for
`victoria-auth/app`.

### Task 2: Platform scrapes (lane A)

**Files:** `kubernetes/utility/apps/observability/victoria-metrics/app/scrapes/` (10 files, one per
object, kustomization entry each).

| File                              | Kind / name                                                  | Selector (namespace)                                                                                | Endpoint                                                                                                                                                                          |
| --------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `vm-kube-apiserver.yaml`          | VMServiceScrape `kube-apiserver`                             | `component=apiserver, provider=kubernetes` (`default`)                                              | `https`, scheme https, SA ca + `serverName: kubernetes`, bearer, job `apiserver`, 2 bucket drops                                                                                  |
| `vm-kubelet.yaml`                 | VMNodeScrape `kubelet`, `kubelet-cadvisor`, `kubelet-probes` | node label `kubernetes.io/os=linux`                                                                 | 10250 `/metrics`, `/metrics/cadvisor`, `/metrics/probes`, https, insecureSkipVerify, bearer, job `kubelet`; keep the 3 / 8 / 0 metric relabel rules from the live config verbatim |
| `vm-kube-etcd.yaml`               | VMStaticScrape `kube-etcd`                                   | —                                                                                                   | `192.168.100.30:2381`, http, bearer                                                                                                                                               |
| `vm-kube-scheduler.yaml`          | VMStaticScrape `kube-scheduler`                              | —                                                                                                   | `192.168.100.30:10259`, https, insecureSkipVerify, bearer                                                                                                                         |
| `vm-kube-controller-manager.yaml` | VMStaticScrape `kube-controller-manager`                     | —                                                                                                   | `192.168.100.30:10257`, https, insecureSkipVerify, bearer                                                                                                                         |
| `vm-coredns.yaml`                 | VMServiceScrape `coredns`                                    | `app=kube-prometheus-stack-coredns, release=kube-prometheus-stack` (`kube-system`)                  | `http-metrics`, bearer, job `coredns`                                                                                                                                             |
| `vm-kube-state-metrics.yaml`      | VMServiceScrape `kube-state-metrics`                         | `app.kubernetes.io/name=kube-state-metrics, app.kubernetes.io/instance=kube-prometheus-stack`       | `http` + `metrics`, `honorLabels: true`, `kubernetes_node` relabel                                                                                                                |
| `vm-node-exporter.yaml`           | VMServiceScrape `node-exporter`                              | `app.kubernetes.io/name=prometheus-node-exporter, app.kubernetes.io/instance=kube-prometheus-stack` | `http-metrics`, `kubernetes_node` relabel                                                                                                                                         |
| `vm-alertmanager.yaml`            | VMServiceScrape `kube-prometheus-stack-alertmanager`         | `app, release=kube-prometheus-stack, self-monitor="true"`                                           | `http-web` + `reloader-web`, job forced                                                                                                                                           |
| `vm-prometheus-operator.yaml`     | VMServiceScrape `kube-prometheus-stack-operator`             | `app, release=kube-prometheus-stack`                                                                | `https`, scheme https, insecureSkipVerify, `honorLabels: true`, job forced                                                                                                        |

`kube-prometheus-stack-prometheus` is **not** mirrored (documented gap: vmagent does not scrape the
Prometheus being retired).

### Task 3: app-owned scrapes (lanes B, C, D)

One `vm-service-scrape.yaml` per app (or `vm-pod-scrape.yaml` for pod targets), listed in that app's
`app/kustomization.yaml`.

**Lane B** — `backup-system`, `cert-manager`, `default`, `flux-system`, `kube-tools`:

| App dir                                 | Object                                | Notes                                                                                                                                                                                                                                    |
| --------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `backup-system/snapshot-controller/app` | VMServiceScrape `snapshot-controller` | `app.kubernetes.io/{instance,name}=snapshot-controller`, port `http`                                                                                                                                                                     |
| `backup-system/volsync/app`             | VMServiceScrape `volsync-metrics`     | `control-plane=volsync-controller`, port `https`, scheme https, insecureSkipVerify, interval 30s                                                                                                                                         |
| `cert-manager/cert-manager/app`         | VMServiceScrape `cert-manager`        | `matchExpressions In`: name ∈ {cainjector,cert-manager,webhook}, instance=cert-manager, component ∈ {cainjector,controller,webhook}; port `http-metrics`, timeout 30s, job from `__meta_kubernetes_service_label_app_kubernetes_io_name` |
| `default/echo-server/app`               | VMServiceScrape `echo-server`         | instance/name/service = echo-server, port `http`                                                                                                                                                                                         |
| `flux-system/flux-operator/app`         | VMServiceScrape `flux-operator`       | instance/name = flux-operator, port `8080`, timeout 30s                                                                                                                                                                                  |
| `kube-tools/descheduler/app`            | VMServiceScrape `descheduler`         | instance/name = descheduler, port `http-metrics`, scheme https, insecureSkipVerify, `honorLabels: true`, job from service label `jobLabel`                                                                                               |

**Lane C** — `kube-system`, `networking`, `secops`, `system-upgrade`, `cnpg-system`, `git-system`:

| App dir                                  | Object                                            | Notes                                                                                                                  |
| ---------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `kube-system/cilium/app`                 | VMServiceScrape `cilium-agent`, `cilium-operator` | `name=cilium-agent` / `io.cilium/app=operator,name=cilium-operator`, port `metrics`, interval 10s, `honorLabels: true` |
| `kube-system/metrics-server/app`         | VMServiceScrape `metrics-server`                  | instance/name = metrics-server, port `https`, scheme https, insecureSkipVerify                                         |
| `networking/external-dns/cloudflare/app` | VMServiceScrape `external-dns-cloudflare`         | `app.kubernetes.io/name=external-dns`, `instance=external-dns-cloudflare`, port `http`                                 |
| `networking/external-dns/unifi/app`      | VMServiceScrape `external-dns-unifi`              | same name label, `instance=external-dns-unifi`, ports `http` + `http-webhook`                                          |
| `secops/pocket-id/app`                   | VMServiceScrape `pocket-id`                       | instance/name/service = pocket-id, port `metrics`                                                                      |
| `system-upgrade/tuppr/app`               | VMServiceScrape `tuppr-metrics-service`           | instance/name = tuppr, port `metrics`, interval 30s                                                                    |
| `cnpg-system/cnpg/operator`              | VMPodScrape `cnpg-operator-cloudnative-pg`        | instance=cnpg-operator, name=cloudnative-pg, port `metrics`, job `cnpg-system/cnpg-operator-cloudnative-pg`            |
| `git-system/forgejo/database`            | VMPodScrape `forgejo-db`                          | `cnpg.io/cluster=forgejo-db`, `cnpg.io/podRole=instance`, port `metrics`, job `git-system/forgejo-db`                  |

**Lane D** — `observability`:

| App dir                                     | Object                                | Notes                                                                                                                                                                                                      |
| ------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `observability/smartctl-exporter/app`       | VMServiceScrape `smartctl-exporter`   | `app.kubernetes.io/name=prometheus-smartctl-exporter`, `instance=smartctl-exporter` (drop the `version`/`helm.sh/chart`/`managed-by` selectors — they churn on every chart bump), port `http`, timeout 30s |
| `observability/vmalert/app`                 | VMServiceScrape `vmalert`             | instance/name/service = vmalert, port `app`                                                                                                                                                                |
| `observability/victoria-logs-collector/app` | VMPodScrape `victoria-logs-collector` | instance/name = victoria-logs-collector, port `http`, job `observability/victoria-logs-collector`                                                                                                          |

### Task 4: README (after Tasks 1–3)

- [ ] Create `kubernetes/utility/apps/observability/victoria-metrics/README.md`: dual-run
      architecture, write path and token, coverage table, gaps (Prometheus self-scrape, utility
      PrometheusRules not mirrored, utility Prometheus stays source of truth), acceptance query
      `count by (cluster) (up)` and how to read it.

### Task 5: validation (coordinator)

- [ ] `kustomize build` every touched app dir and `kubectl --context readonly@utility apply
--dry-run=client` the output.
- [ ] `npx prettier --check` the touched files.
- [ ] Cross-check every object against the live Prometheus config: same job names, same ports,
      same intervals.
- [ ] Commit in reviewable slices, open PR, report URL.

## Acceptance

`count by (cluster) (up)` against `https://metrics.techtales.io` returns `main` and `utility`;
`up{cluster="utility",job="node-exporter"}` and the kubelet/apiserver jobs exist.
