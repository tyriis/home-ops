# Cilium Hubble Enablement (main) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Hubble on for the main cluster — relay plus flow metrics scraped by both the Prometheus and
VictoriaMetrics paths, with the four chart-shipped dashboards imported into Grafana — so network-policy work has
observed flows instead of guesses.

**Architecture:** `hubble.enabled` and `hubble.relay.enabled` are flipped in the existing Cilium HelmRelease (agents
already roll on config change, `rollOutCiliumPods: true`). Metrics are described twice, because run 1 of the
VictoriaMetrics migration is a dual-run: a `ServiceMonitor` for Prometheus (still Grafana's source of truth) and a
`VMServiceScrape` for the central store. Dashboards are Grafana Operator `GrafanaDashboard` resources pointing at
the ConfigMaps the chart already renders.

**Tech Stack:** Flux HelmRelease (chart `cilium` 1.20.4), Cilium/Hubble, kube-prometheus-stack, VictoriaMetrics
operator, Grafana Operator, kustomize + `flate`.

**Spec:** issue [#10183](https://github.com/tyriis/home-ops/issues/10183), design summary below. Issue body to
paste: `/tmp/opencode/issue-10183.md`.

## Design summary

**Approaches considered**

- **A — relay only.** `hubble.enabled` + `relay.enabled`. Smallest change; flow visibility only
  through `hubble observe` over a port-forward, no history, nothing in Grafana.
- **B — relay + metrics + dashboards (chosen).** Adds both scrape dialects and the four dashboard ConfigMaps the
  chart already ships but nobody imports. Flow data becomes queryable and retained, and policy authoring reads a
  dashboard instead of a shell.
- **C — B + Hubble UI.** Adds a Deployment plus an HTTPRoute and pocket-id `SecurityPolicy`. The UI ships with no
  authentication of its own, so it is only acceptable behind SSO, and it is the one part that may not earn its keep.
  Deferred.

**Decisions taken**

- **Main only.** Utility keeps its `hubble.enabled: false` and its own FIXME; that is a separate change
  (`kubernetes/utility/apps/kube-system/cilium/`).
- **No UI.** Out of scope here; if it is wanted later it is an `hubble.ui` block plus an
  `HTTPRoute`/`SecurityPolicy` pair in `kubernetes/main/apps/kube-system/cilium/app/`, following
  `kubernetes/main/apps/ai/mcp-context7/app/`.
- **Relay's own metrics (`hubble.relay.prometheus`, port 9966) are not scraped.** Only the agent-side flow metric
  groups the HelmRelease already lists.
- **TLS stays on the chart defaults** (`hubble.tls.enabled: true`, `auto.method: helm`). No cert-manager wiring: the
  chart signs leaf certs from the `cilium-ca` Secret it already creates.
- **Bootstrap keeps parity** for `enabled`/`relay.enabled` only. It must not set the `ServiceMonitor`: at bootstrap
  time kube-prometheus-stack (and the `monitoring.coreos.com` CRDs) do not exist yet.

**Facts the plan depends on (verified against chart 1.20.4)**

| Fact | Value |
| --- | --- |
| `hubble.enabled` chart default | `true` — the repo's `false` is a deliberate override |
| `hubble.relay.enabled` chart default | `false` |
| `hubble.metrics.enabled` chart default | `~` (metrics off) |
| `hubble.metrics.port` | `9965` |
| Metrics Service | `hubble-metrics`, headless, selector `k8s-app: cilium`, port name `hubble-metrics` |
| Peer Service | `hubble-peer`, port `443` (TLS on) → `targetPort 4244` |
| `hubble.metrics.serviceMonitor.enabled` alone | renders nothing — needs a non-empty `hubble.metrics.enabled` |
| Dashboard ConfigMaps (basename → data key) | `hubble-dashboard`, `hubble-dns-namespace`, `hubble-l7-http-metrics-by-workload`, `hubble-network-overview-namespace`; key `<name>.json` |
| Dashboard datasource input | `DS_PROMETHEUS` in all four |
| Prometheus job for the new target | `kube-system/hubble-metrics` |
| VictoriaMetrics job for the new target | `hubble-metrics` (the selected Service's name, per `kubernetes/main/apps/observability/victoria-metrics/README.md:292`) |
| Existing dashboard ConfigMaps | all four already exist in `kube-system` |

## Global Constraints

- Main cluster **only**. Do not touch `kubernetes/utility/**` or either bootstrap tree outside
  `kubernetes/main/bootstrap/cilium/`.
- Cilium chart version stays `1.20.4`; this change does not bump it.
- Never commit plaintext secrets. The Hubble cert Secrets are chart-rendered; nothing secret is added to git.
- Comments follow the repo rule: anchors, cross-file constraints, traps, provenance only. No "what this does"
  narration, no commented-out YAML kept "just in case".
- Every git commit message: `<type>(<scope>): <description>`, imperative, ≤ 72 characters, scope `cilium`.
- Branch name: `feature/cilium-hubble-enablement` (must match `<bugfix|feature>/<kebab-case>`, ≤ 40 chars).
- The implementer is **authorized and expected** to add whatever the repo's gates need (schema comment lines,
  kustomization entries, lint suppressions) to pass `task lint:*`,
  `task deadvalues:check-values`, `task flate:diff -- main` and `task flate:test -- main`.

## Review Focus

- **TLS non-idempotence.** The chart's `tls-helm` templates reuse leaf certs via `lookup` but always re-render
  `ca.crt` from `cilium-ca`. A render performed without cluster access (`helm template`, some dry-runs) produces a
  CA that does not match the live leaves; applying it breaks relay↔agent mTLS with
  `x509: certificate signed by unknown authority`. Expect `cilium-ca` and the leaf Secrets to be
  byte-identical before and after the upgrade.
- **Agent rollout timing.** `enable-hubble` is a `cilium-config` key read at agent start; the repo's
  `rollOutCiliumPods: true` covers it. If it were false, `hubble-peer` would have no backend and relay would log
  `connect: connection refused`.
- **Selector confusion.** `k8s-app: hubble` labels the *metrics Service*, not the agent pods (which carry
  `k8s-app: cilium`). A `VMServiceScrape` selecting `k8s-app: palindrome`-style typos, or copying the agent scraper's
  `app.kubernetes.io/name: cilium-agent` selector, silently yields an empty job.
- **Two different `cluster` values exist, and neither query is wrong.** Prometheus `externalLabels.cluster` and the
  `VMAgent` both say `main`, but `cilium-config` reports `cluster-name: kube-lab` because
  `kubernetes/main/apps/kube-system/cilium/flux-sync.yaml:25` hardcodes `FLUX_CLUSTER_NAME: kube-lab` behind its own
  FIXME. The hubble metric queries below select `cluster="main"`; the `kube-lab` value is a pre-existing wart and is
  **not** fixed in this change.
- **Dashboards read Prometheus, not VictoriaMetrics.** Run 1 keeps Grafana on the `prometheus` datasource, so the
  dashboards only fill once the `ServiceMonitor` path is up; a green series in the central store says nothing about
  the Grafana view.
- **`deadvalues` false positives.** New values keys are only "live" while their gate is true — with an empty
  `hubble.metrics.enabled` list, `hubble.metrics.serviceMonitor.enabled` renders nothing and can be reported dead.

---

### Task 1: Enable Hubble and Relay on main

**Files:**
- Modify: `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml:51-95` (the `hubble:` block)
- Modify: `kubernetes/main/bootstrap/cilium/values.yaml:23-26` (the `hubble:` block)

**Interfaces:**
- Consumes: nothing.
- Produces: `hubble.enabled: true`, `hubble.relay.enabled: true` in both the HelmRelease and the bootstrap values;
  the `hubble-peer` Service becomes live, `hubble-relay` Deployment appears in `kube-system`.

- [ ] **Step 1: Rewrite the HelmRelease hubble block**

Replace lines 51–95 of `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml` so the block reads exactly:

```yaml
    hubble:
      enabled: true
      relay:
        enabled: true
        resources:
          requests:
            cpu: 25m
            memory: 128Mi
          limits:
            memory: 512Mi
      metrics:
        enabled:
          - dns:query;ignoreAAAA
          - drop
          - tcp
          - flow
          - port-distribution
          - icmp
          - http
        dashboards:
          enabled: true
          annotations:
            grafana_folder: Cilium
```

This deletes the `# FIXME`, the `# Read only when hubble.enabled is true` comment pair, the commented
`serviceMonitor` stanza (replaced for real in Task 2) and the entire commented Traefik-era `ui` block (lines 70–95)
— Traefik no longer runs here, and a "re-enable together with it" comment now points at a setting that is on.

- [ ] **Step 2: Mirror the two toggles in the bootstrap values**

Replace lines 23–26 of `kubernetes/main/bootstrap/cilium/values.yaml` with:

```yaml
hubble:
  enabled: true
  relay:
    enabled: true
```

Do not add `hubble.metrics` here: bootstrap runs before kube-prometheus-stack installs the `monitoring.coreos.com`
CRDs, and a ServiceMonitor in that render would fail to apply.

- [ ] **Step 3: Render both trees**

Run: `kubectl kustomize --enable-helm kubernetes/main/bootstrap/cilium | grep -A4 'relay:'`
Expected: `hubble-relay` Deployment and Service present in the rendered output, no error.

Run: `task flate:diff -- main`
Expected: the diff lists only `cilium` HelmRelease values changes plus the intended new/updated objects; no
unrelated cluster churn.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml kubernetes/main/bootstrap/cilium/values.yaml
git commit -m "feat(cilium): enable hubble and hubble relay on main"
```

- [ ] **Step 5: Reconcile and confirm the agents rolled**

Run: `flux reconcile helmrelease cilium -n kube-system --with-source` (or wait for the 30m interval), then:
`kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}'`
Expected: `3/3 ready=3` — one cilium agent per main node (`talos01-03`). A count that stays at `0/3` means the
DaemonSet did not roll; check `rollOutCiliumPods` is still `true`.

Run: `kubectl -n kube-system get pods -l k8s-app=hubble-relay -o wide`
Expected: one `hubble-relay-*` pod `1/1 Running`. Readiness is a real health check on port 4222, so `1/1` means the
relay came up rather than merely started.

Run: `kubectl -n kube-system logs deploy/hubble-relay --tail=20`
Expected: no `connection refused`; the config the relay loaded names the peer service
(`hubble-peer.kube-system.svc.cluster.local:443`).

Run: `kubectl -n kube-system get secret cilium-ca hubble-server-certs hubble-relay-client-certs`
Expected: all three exist.

- [ ] **Step 6: Confirm the client credentials the relay mounts**

Run: `kubectl -n kube-system get secret hubble-relay-client-certs -o jsonpath='{.data}'`
Expected: keys `client.crt`, `client.key`, `hubble-server-ca.crt` present (values are base64). The flow counts
themselves come from Task 2 — until the metrics path exists there is nothing to query.

Optional, only if a `hubble` CLI is available locally: port-forward the relay Service
(`kubectl -n kube-system port-forward svc/hubble-relay 4245:80`; the Service maps port 80 to `grpc`), then
`hubble observe --server localhost:4245` with the `hubble-relay-client-certs` material copied out.

---

### Task 2: Scrape Hubble metrics on both paths

**Files:**
- Modify: `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml` (inside the `hubble.metrics` block from
  Task 1)
- Modify: `kubernetes/main/apps/kube-system/cilium/app/vm-service-scrape.yaml` (append one object)

**Interfaces:**
- Consumes: `hubble.metrics.enabled` (non-empty) and the `hubble-metrics` Service from Task 1.
- Produces: Prometheus target job `kube-system/hubble-metrics`, VictoriaMetrics job `hubble-metrics`;
  `hubble_drop_total`, `hubble_flows_processed_total`, `hubble_tcp_flags_total`, `hubble_dns_queries_total`,
  `hubble_http_requests_total`, `hubble_icmp_total`, `hubble_port_distribution_total` series in both stores.

- [ ] **Step 1: Enable the chart's ServiceMonitor**

Insert under `hubble.metrics` in the HelmRelease, immediately after the `enabled:` metric list and before `dashboards:`:

```yaml
        serviceMonitor:
          enabled: true
```

- [ ] **Step 2: Add the VictoriaMetrics scrape**

Append to `kubernetes/main/apps/kube-system/cilium/app/vm-service-scrape.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/operator.victoriametrics.com/vmservicescrape_v1beta1.json
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: hubble
spec:
  namespaceSelector:
    matchNames:
      - kube-system
  selector:
    matchLabels:
      k8s-app: hubble
  endpoints:
    - port: hubble-metrics
      honorLabels: true
      path: /metrics
      interval: 10s
  targetLabels:
    - k8s-app
```

`k8s-app: hubble` labels the metrics Service; `k8s-app: cilium` labels the agent pods behind it and is the wrong
selector here.

- [ ] **Step 3: Check the objects render and no value is dead**

Run: `kubectl kustomize kubernetes/main/apps/kube-system/cilium/app | grep -c 'kind: VMServiceScrape'`
Expected: `3` (cilium-operator, cilium-agent, hubble).

Run: `task deadvalues:check-values-changed`
Expected: exit 0. A `hubble.metrics.serviceMonitor.enabled` finding means the metric list is empty in the rendered
values — fix the list, not the check.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml kubernetes/main/apps/kube-system/cilium/app/vm-service-scrape.yaml
git commit -m "feat(cilium): scrape hubble flow metrics on both paths"
```

- [ ] **Step 5: Confirm both scrapers pick the target up**

Run: `kubectl -n kube-system get servicemonitor hubble -o jsonpath='{.spec.endpoints[0].port}'`
Expected: `hubble-metrics`.

Run: `kubectl -n kube-system get vmservicescrape hubble`
Expected: present, no error.

Prometheus (run 1's source of truth), via port-forward to `svc/prometheus-operated -n observability`:
```
count(up{job="kube-system/hubble-metrics"} == 1)
```
Expected: `3` — one per cilium agent, matching the node count.

```
count(hubble_flows_processed_total{cluster="main"}) > 0
```
Expected: `1` (the series exist). Then, after generating traffic (browse a couple of internal UIs, or curl any
Service from a pod):

```
sum(rate(hubble_flows_processed_total{cluster="main"}[5m])) > 0
```
Expected: a non-zero rate. Series that exist but never move mean the agent's flow buffer is not being fed — check
the relay pod is still `1/1` and its logs show no `connection refused`.

Central store, via `https://metrics.techtales.io` with the read token:
```
count(up{cluster="main", job="hubble-metrics"} == 1)
```
Expected: `3`. Zero means the selector or port name is wrong (see Review Focus).

```
count(hubble_drop_total{cluster="main"}) > 0
```
Expected: a non-zero count.

---

### Task 3: Import the four Hubble dashboards

**Files:**
- Modify: `kubernetes/main/apps/kube-system/cilium/app/grafana-dashboard.yaml` (append four objects)

**Interfaces:**
- Consumes: the ConfigMaps `hubble-dashboard`, `hubble-dns-namespace`, `hubble-l7-http-metrics-by-workload`,
  `hubble-network-overview-namespace` in `kube-system` (already rendered today by
  `hubble.metrics.dashboards.enabled: true`).
- Produces: four `GrafanaDashboard` resources that make those ConfigMaps visible in Grafana.

- [ ] **Step 1: Append four GrafanaDashboard resources**

Append to `kubernetes/main/apps/kube-system/cilium/app/grafana-dashboard.yaml`, one object per dashboard, each
carrying the same header and datasource wiring as the existing two in that file:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/grafana.integreatly.org/grafanadashboard_v1beta1.json
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: hubble
spec:
  allowCrossNamespaceImport: true
  instanceSelector:
    matchLabels:
      grafana.internal/instance: grafana
  datasources:
    - datasourceName: prometheus
      inputName: DS_PROMETHEUS
  # created by cilium
  configMapRef:
    name: hubble-dashboard
    key: hubble-dashboard.json
```

Repeat with `metadata.name` / `configMapRef.name` / `configMapRef.key` set to, in turn:

| `metadata.name` | `configMapRef.name` | `configMapRef.key` |
| --- | --- | --- |
| `hubble-dns-namespace` | `hubble-dns-namespace` | `hubble-dns-namespace.json` |
| `hubble-l7-http-metrics-by-workload` | `hubble-l7-http-metrics-by-workload` | `hubble-l7-http-metrics-by-workload.json` |
| `hubble-network-overview-namespace` | `hubble-network-overview-namespace` | `hubble-network-overview-namespace.json` |

Every one of the four chart dashboards declares `DS_PROMETHEUS` as its only input, which is why the datasource
mapping is identical to the existing `cilium` resource.

- [ ] **Step 2: Lint the manifest**

Run: `task lint:yaml`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/kube-system/cilium/app/grafana-dashboard.yaml
git commit -m "feat(cilium): import hubble dashboards into grafana"
```

- [ ] **Step 4: Confirm the operator imported them**

Run: `kubectl -n kube-system get grafanadashboard`
Expected: `hubble`, `hubble-dns-namespace`, `hubble-l7-http-metrics-by-workload`,
`hubble-network-overview-namespace` alongside `cilium` and `cilium-operator`.

In Grafana, open **Hubble Metrics and Monitoring** and confirm the panels populate. Empty panels with a populated
`up{job="kube-system/hubble-metrics"}` means a datasource-input mismatch; empty `up` means Task 2 did not land.

---

### Task 4: Whole-change verification

**Files:** none — verification only.

**Interfaces:**
- Consumes: Tasks 1–3 merged and reconciled.
- Produces: the evidence quoted in the pull request.

- [ ] **Step 1: Static gates**

```bash
task flate:diff -- main
task flate:test -- main
task lint:yaml
task lint:prettier
task deadvalues:check-values-changed
```
Expected: all exit 0. Paste the `flate diff` summary into the PR: it is the review's only view of what actually
changes on the cluster.

- [ ] **Step 2: Cluster state**

```bash
kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}'
kubectl -n kube-system get pods | grep -E 'hubble'
kubectl -n kube-system get svc hubble-peer hubble-metrics
```
Expected: agents all ready, `hubble-relay-*` running, `hubble-peer` on 443→4244, `hubble-metrics` headless on 9965.

- [ ] **Step 3: Flow and metric evidence**

```bash
kubectl -n kube-system get pods -l k8s-app=hubble-relay
kubectl -n kube-system logs deploy/hubble-relay --tail=30
```
Then the two counts from Task 2 Step 5 against Prometheus and against the central store, one
`rate(hubble_flows_processed_total[5m])` sample, and one dashboard screenshot.

- [ ] **Step 4: Report the follow-up, do not do it here**

Record in the PR description that **TCP 4244 must stay reachable between nodes** and that `kube-dns` plus
`hubble-peer:443` are the two allow-rules the default-deny rollout (the netpol follow-up under #8068) has to carry
from day one. No policy objects are added by this plan — policy `enable-policy` stays `default`.
