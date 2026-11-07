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
- **TLS through cert-manager** (`hubble.tls.enabled: true`, `auto.method: certmanager`,
  `certManagerIssuerRef: hubble-ca`). The chart signs no CA of its own on this path: it renders `Certificate`
  objects whose `secretName` is exactly what the agent and relay mount, and cert-manager renews them at two thirds of
  their lifetime. The repo has no CA-backed issuer, only ACME (cannot sign `*.hubble-grpc.cilium.io`) and a bare
  `selfSigned` (a self-signed leaf trusts nothing), so this change adds a private CA: selfsigned Issuer →
  `isCA` Certificate → `ca` Issuer, the same shape as `kubernetes/main/apps/kube-tools/k8tz/app/pki.yaml`.
- **Bootstrap stays off.** `kubernetes/main/bootstrap/cilium/values.yaml` keeps `hubble.enabled: false`. Its
  `cluster.name` is `main` while the HelmRelease renders `kube-lab` (the `cilium/flux-sync.yaml` FIXME), and the
  chart derives the Hubble server cert SAN from `cluster.name` (`*.<cluster-name>.hubble-grpc.cilium.io`). Enabling
  hubble at bootstrap would mint a `*.main.…` leaf that the HelmRelease's `lookup` then pins while pointing the relay
  at `hubble-peer.kube-lab.…` — relay↔agent mTLS fails on every fresh bootstrap. The ServiceMonitor must stay out of
  bootstrap too: the `monitoring.coreos.com` CRDs do not exist at that point.

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
| Prometheus job for the new target | `hubble-metrics` — the ServiceMonitor sets no `jobLabel`, so the operator relabels `job` from the Service name |
| VictoriaMetrics job for the new target | `hubble-metrics` (also the selected Service's name, per `kubernetes/main/apps/observability/victoria-metrics/README.md:292`) |
| Existing dashboard ConfigMaps | all four already exist in `kube-system` |
| `hubble.tls.auto.method: certmanager` | renders `Certificate`s only, no CA; the issuer it is given must be CA-backed |
| Agent `hubble-tls` volume | `optional: true` — missing certificates never block an agent pod |
| Relay `tls` volume | not optional — missing certificates leave the relay `Pending` |

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

- **TLS now depends on cert-manager.** `method: certmanager` makes the chart render three `Certificate` objects
  (`hubble-server-certs`, `hubble-relay-client-certs`, `hubble-relay-server-certs`) and no CA of its own. Two
  consequences. (a) The private CA (`hubble-selfsign` → `hubble-ca` Certificate → `hubble-ca` Issuer) must exist in
  `kube-system` before those certificates can issue; until it does, the relay pod stays `Pending` on its non-optional
  TLS volume while the agents keep running (their `hubble-tls` volume is `optional: true`). (b) cert-manager owns
  renewal: leaves last 365 days and renew at two thirds, the CA lasts 5 years and renews the same way. Check
  `kubectl -n kube-system get certificate` is all `Ready` and record the `notAfter` dates in the PR.
- **The bootstrap divergence is unchanged by the TLS method.** Bootstrap renders `cluster.name: main`, the
  HelmRelease renders `kube-lab`, and the server cert's SAN follows `cluster.name`. With cert-manager the leaf is
  issued from the live `cluster.name`, so a bootstrap-side hubble enablement would still hand cert-manager an
  `*.main.…` request to pin. Hubble stays off in the bootstrap tree.
- **Agent rollout timing.** `enable-hubble` is a `cilium-config` key read at agent start; the repo's
  `rollOutCiliumPods: true` covers it. If it were false, `hubble-peer` would have no backend and relay would log
  `connect: connection refused`.
- **Selector confusion.** `k8s-app: hubble` labels the *metrics Service*, not the agent pods (which carry
  `k8s-app: cilium`). A `VMServiceScrape` selecting `k8s-app: palindrome`-style typos, or copying the agent scraper's
  `app.kubernetes.io/name: cilium-agent` selector, silently yields an empty job.
- **`cluster="main"` works in the central store only.** Prometheus `externalLabels` are applied on the remote-write
  path, not to local queries, so `hubble_flows_processed_total{cluster="main"}` is empty against Prometheus itself
  and populated against `metrics.techtales.io`. The `VMAgent` adds `cluster: main`. Separately, `cilium-config`
  reports `cluster-name: kube-lab` because `kubernetes/main/apps/kube-system/cilium/flux-sync.yaml:25` hardcodes
  `FLUX_CLUSTER_NAME: kube-lab` behind its own FIXME — that is a pre-existing wart and is **not** fixed here.
- **Dashboards read Prometheus, not VictoriaMetrics.** Run 1 keeps Grafana on the `prometheus` datasource, so the
  dashboards only fill once the `ServiceMonitor` path is up; a green series in the central store says nothing about
  the Grafana view.
- **`deadvalues` false positives.** New values keys are only "live" while their gate is true — with an empty
  `hubble.metrics.enabled` list, `hubble.metrics.serviceMonitor.enabled` renders nothing and can be reported dead.

## Decisions taken during review

1. **Cert renewal — decided: cert-manager.** The chart's `helm` method mints 365-day leaves and pins them across
   upgrades (`lookup`), so mTLS would die silently a year in. `method: certmanager` hands the same Secrets to
   cert-manager, which renews at two thirds of lifetime. Cost, accepted: a private CA has to exist in the cluster
   (this change adds one) and the relay cannot start while cert-manager is unhealthy — the relay's TLS volume is not
   optional, so it stays `Pending` instead of coming up without certs. The agent's volume *is* optional, so a
   cert-manager outage never blocks a CNI rollout or cluster networking.
2. **Relay authentication — decided: mTLS.** `hubble.relay.tls.server.enabled: true` with `mtls: true`. The relay
   now presents `hubble-relay-server-certs` and verifies client certs against the same CA, so a pod without a
   certificate cannot read flows from `hubble-relay.kube-system:80`. Clients (`hubble observe`, a future UI) need a
   cert signed by that CA — the relay's own client pair in `hubble-relay-client-certs` works for the CLI. Note this
   is a chart-level boolean, not an object: `hubble.relay.tls.server.mtls: true` (the schema rejects a mapping).

---

### Task 1: Enable Hubble, its private CA and the relay on main

**Files:**
- Modify: `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml:51-95` (the `hubble:` block)
- Create: `kubernetes/main/apps/kube-system/cilium/app/hubble-pki.yaml`
- Modify: `kubernetes/main/apps/kube-system/cilium/app/kustomization.yaml`

**Interfaces:**
- Consumes: cert-manager (`cert-manager.io/v1` CRDs) on main.
- Produces: `hubble.enabled: true`, `hubble.relay.enabled: true`, `hubble.relay.rollOutPods: true`,
  `hubble.tls.auto.method: certmanager` pointing at the `hubble-ca` Issuer; the `hubble-peer` Service, the
  `hubble-relay` Deployment, and the `hubble-ca` Issuer/Certificate. `kubernetes/main/bootstrap/cilium/values.yaml`
  is deliberately untouched.

- [ ] **Step 1: Rewrite the HelmRelease hubble block**

Replace lines 51–95 of `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml` so the block reads exactly:

```yaml
    hubble:
      enabled: true
      tls:
        auto:
          method: certmanager
          certManagerIssuerRef:
            group: cert-manager.io
            kind: Issuer
            name: hubble-ca
      relay:
        enabled: true
        rollOutPods: true
        tls:
          server:
            enabled: true
            mtls: true
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

`mtls` is a boolean on this chart (`hubble.relay.tls.server.mtls: true`); a mapping fails schema validation.

- [ ] **Step 2: Create the private CA**

`certmanager` issues leaves from whatever issuer it is pointed at, and this repo only has ACME issuers (cannot sign
`*.hubble-grpc.cilium.io`) and a bare `selfSigned` (a self-signed leaf trusts nothing). Create
`kubernetes/main/apps/kube-system/cilium/app/hubble-pki.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cert-manager.io/issuer_v1.json
# Private CA for Hubble's mTLS: selfsigned root -> CA certificate -> CA issuer.
# The ACME ClusterIssuers cannot sign *.hubble-grpc.cilium.io, and cert-manager's
# certmanager method signs leaves directly, so the referenced issuer must be CA-backed.
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: hubble-selfsign
spec:
  selfSigned: {}
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hubble-ca
spec:
  secretName: hubble-ca
  duration: 43800h
  commonName: ca.hubble.cilium.io
  isCA: true
  issuerRef:
    name: hubble-selfsign
    kind: Issuer
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/cert-manager.io/issuer_v1.json
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: hubble-ca
spec:
  ca:
    secretName: hubble-ca
```

Then add `- ./hubble-pki.yaml` to the `resources:` list in
`kubernetes/main/apps/kube-system/cilium/app/kustomization.yaml`. Namespace is not set here: the Flux Kustomization
stamps `targetNamespace: kube-system`.

- [ ] **Step 3: Leave the bootstrap values alone**

`kubernetes/main/bootstrap/cilium/values.yaml` keeps `hubble.enabled: false` / `relay.enabled: false`. This is the
one place the plan deliberately does **not** mirror the HelmRelease: bootstrap renders `cluster.name: main`, the
HelmRelease renders `kube-lab`, and the Hubble server cert SAN is derived from `cluster.name`. Enabling hubble at
bootstrap creates `hubble-server-certs` for `*.main.hubble-grpc.cilium.io`; the first Flux upgrade keeps that leaf
(`lookup`) but writes `cluster-name: kube-lab` into `hubble-relay-config`, so the relay looks for
`hubble-peer.kube-lab.hubble-grpc.cilium.io` and never becomes ready. Bootstrap also has no cert-manager yet. Only
mirror this file after the `FLUX_CLUSTER_NAME` FIXME in
`kubernetes/main/apps/kube-system/cilium/flux-sync.yaml` is resolved so both sides agree.

Do not add `hubble.metrics` there either: bootstrap runs before kube-prometheus-stack installs the
`monitoring.coreos.com` CRDs, and a ServiceMonitor in that render would fail to apply.

- [ ] **Step 4: Render both trees**

Run: `kubectl kustomize kubernetes/main/apps/kube-system/cilium/app > /tmp/cilium-app.yaml`
Expected: exit 0; `grep -c '^kind: Certificate' /tmp/cilium-app.yaml` prints `1` (`hubble-ca`) and
`grep -c '^kind: Issuer'` prints `2` (`hubble-selfsign`, `hubble-ca`). The unanchored pattern also matches the
`issuerRef` inside the HelmRelease values, which is why both greps are anchored.

Run: `helm template cilium cilium --repo https://helm.cilium.io/ --version 1.20.4 -n kube-system -f kubernetes/main/bootstrap/cilium/values.yaml | grep -c hubble-relay`
Expected: `0` — a non-zero count means Step 3 was skipped.

The leaf certificates are chart-rendered from the HelmRelease values, so they only appear once Flux applies it; Step 6
asserts them on the cluster. CI's `flate diff` renders the HelmRelease itself and shows the three `Certificate`
objects in the PR.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml \
        kubernetes/main/apps/kube-system/cilium/app/hubble-pki.yaml \
        kubernetes/main/apps/kube-system/cilium/app/kustomization.yaml
git commit -m "feat(cilium): enable hubble and hubble relay on main"
```

- [ ] **Step 6: Reconcile and confirm certs, agents and relay**

Run: `flux reconcile kustomization cilium -n kube-system --with-source` and
`flux reconcile helmrelease cilium -n kube-system --with-source` (or wait for the 30m interval).

Run: `kubectl -n kube-system get certificate`
Expected: `hubble-ca`, `hubble-server-certs`, `hubble-relay-client-certs`, `hubble-relay-server-certs` all `Ready`
`True`. A `Certificate` that stays `False` names its reason in the message column — an issue with `hubble-ca`
(a missing/broken private CA) blocks the other three.

Run: `kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}'`
Expected: `3/3` — one cilium agent per main node (`talos01-03`). A count that stays at `0/3` means the DaemonSet did
not roll; check `rollOutCiliumPods` is still `true`.

Run: `kubectl -n kube-system get pods -l k8s-app=hubble-relay -o wide`
Expected: one `hubble-relay-*` pod `1/1 Running`. Readiness is a real health check on port 4222, so `1/1` means the
relay came up rather than merely started. A pod stuck `Pending` is almost always a missing TLS Secret.

Run: `kubectl -n kube-system logs deploy/hubble-relay --tail=20`
Expected: no `connection refused`; the config the relay loaded names the peer service
(`hubble-peer.kube-system.svc.cluster.local.:443`).

- [ ] **Step 7: Confirm the credentials the agent and relay mount**

Run: `kubectl -n kube-system get secret hubble-ca hubble-server-certs hubble-relay-client-certs hubble-relay-server-certs -o jsonpath='{range .items[*]}{.metadata.name}: {.data}{"\n"}{end}'`
Expected: keys `ca.crt`, `tls.crt`, `tls.key` on each leaf (`hubble-ca` also carries `tls-computing.crt`, which is
fine). `client.crt` / `client.key` / `hubble-server-ca.crt` are the projected-volume filenames inside the relay pod,
not Secret keys.

Optional, only if a `hubble` CLI is available locally: port-forward the relay Service
(`kubectl -n kube-system port-forward svc/hubble-relay 4245:80`; the Service maps port 80 to `grpc`), then
`hubble observe --server localhost:4245 --tls` with the CA and client pair taken from `hubble-relay-client-certs`
(`ca.crt` as `--tls-ca-cert-files`, `tls.crt`/`tls.key` as `--tls-client-cert-file`/`--tls-client-key-file`).
Relay mTLS is on, so a plain `hubble observe` is refused by design.

---

### Task 2: Scrape Hubble metrics on both paths

**Files:**
- Modify: `kubernetes/main/apps/kube-system/cilium/app/helm-release.yaml` (inside the `hubble.metrics` block from
  Task 1)
- Modify: `kubernetes/main/apps/kube-system/cilium/app/vm-service-scrape.yaml` (append one object)

**Interfaces:**
- Consumes: `hubble.metrics.enabled` (non-empty) and the `hubble-metrics` Service from Task 1.
- Produces: Prometheus target job `hubble-metrics` and VictoriaMetrics job `hubble-metrics` (both take the selected
  Service's name);
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
count(up{job="hubble-metrics"} == 1)
```
Expected: `3` — one per cilium agent, matching the node count.

```
count(hubble_flows_processed_total) > 0
```
Expected: `1` (the series exist). Then, after generating traffic (browse a couple of internal UIs, or curl any
Service from a pod):

```
sum(rate(hubble_flows_processed_total[5m])) > 0
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
`up{job="hubble-metrics"}` means a datasource-input mismatch; empty `up` means Task 2 did not land.
`hubble-l7-http-metrics-by-workload` is expected to stay empty until an L7 policy exists: the `http` handler only
emits `hubble_http_*` when L7 flow parsing is active. Check the DNS, TCP, drop and flow panels instead.

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
kubectl -n kube-system get certificate
kubectl -n kube-system get ds cilium -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}'
kubectl -n kube-system get pods | grep -E 'hubble'
kubectl -n kube-system get svc hubble-peer hubble-metrics
```
Expected: four `Certificate`s `Ready` (`hubble-ca` valid 5y, the three leaves 365d), agents all ready,
`hubble-relay-*` running, `hubble-peer` on 443→4244, `hubble-metrics` headless on 9965. Record the leaf `notAfter`
dates in the PR — cert-manager renews them at two thirds, and the dates are what shows renewal still works.

- [ ] **Step 3: Flow and metric evidence**

```bash
kubectl -n kube-system get pods -l k8s-app=hubble-relay
kubectl -n kube-system logs deploy/hubble-relay --tail=30
```
Then the two counts from Task 2 Step 5 against Prometheus and against the central store, one
`rate(hubble_flows_processed_total[5m])` sample, and one dashboard screenshot.

- [ ] **Step 4: Report the follow-up, do not do it here**

Record in the PR description that the default-deny rollout owes **`hubble-relay` → `cilium` on TCP 4244** (the
`hubble-peer` Service is `internalTrafficPolicy: Local`, so this is node-local, not a node-to-node rule), plus
`kube-dns` for DNS, plus the relay's own ingress on 4245 for whichever client certificate holder observes flows. These
belong to the netpol follow-up under #8068. No policy objects are added by this plan — `enable-policy` stays
`default`.
