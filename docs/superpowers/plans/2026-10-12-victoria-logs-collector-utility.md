# victoria-logs-collector on utility — Implementation Plan (Phase 2, utility shipper)

**Goal:** Ship util01's pod + node logs to the central VictoriaLogs via the official
`victoria-logs-collector` Helm chart (binary **vlagent**), pushing through vmauth
(in-cluster `vmauth` service, `http://vmauth.observability.svc.cluster.local:8427/insert/jsonline`) with the existing `utility` write token.

**Scope:** utility cluster only. Main cluster, NAS, bifrost, workstation, remote-site shippers
are separate phase-2 slices (ADR 0016 lists them; each reuses this pattern with its own token).

**Decided defaults** (flip any of these before implementing):

| Question | Default | Why |
| --- | --- | --- |
| Token storage | Read key `VMAUTH_TOKEN_UTILITY` from the existing `vmauth-tokens` Secret via `secretKeyRef` | One source of truth; the collector's pod is recreated anyway when vmauth rotates the key |
| Own-logs loop | `collector.excludeFilter` drops the collector pod itself | DaemonSet would otherwise tail its own stdout forever |
| Buffer | hostPath `/var/lib/vl-collector` (chart default), `maxDiskUsagePerURL: 1Gi` | Survives collector + node restarts; cap protects the SSD |
| Talos change | **None** | hostPath allowlist doesn't exist on Talos 1.14; promtail on main already proves `/var/log` tailing works |
| Version pin | chart `0.3.8`, vlagent `v1.53.0` | Same release train as the deployed VL v1.53.0 |

**Facts baked in (verified 2026-10-12):**

- The chart deploys **vlagent** (VictoriaLogs' own Go agent — *not* fluent-bit, *not* a logproxy
  fork). DaemonSet, port **9429** (metrics + ingest), SA auto-created, ClusterRole =
  `nodes, namespaces, pods` → `get,list,watch` only.
- Collection = tail files under `/var/log/pods` (read-only hostPaths `/var/log`, `/var/lib` are
  chart defaults) + K8s API metadata enrichment. **No kubelet-API/containerLogs mode exists.**
- On-disk per-destination send-buffer + tail-offset checkpoints live in writable hostPath
  `/var/lib/vl-collector` (`tmpDataPath`) → covers R6 (utility restarts, no re-send/no loss).
- `envflag.enable: true` + `envflag.prefix: VL_` are chart defaults → `%{VAR}` expansion works
  inside flag values, so `Authorization: Bearer %{VL_TOKEN}` keeps the token out of the manifest.
- vmauth route is `/insert/.*` write-only; query strings pass through; vlagent pushes jsonline
  with zstd — vmauth proxies `Content-Encoding` transparently. VL single-node → tenant `0:0`,
  no `accountID/projectID` needed (chart injects `AccountID:0/ProjectID:0` headers; VL ignores).
- vmauth netpol today allows ingress to `:8427` **only** from ns `networking` → the collector
  needs a new allow rule (same-namespace pods), or it will blackhole on first push.
- Chart dep `victoria-metrics-common 0.4.*` resolves from `oci://ghcr.io/victoriametrics/helm-charts`
  — helm-controller handles it (victoria-logs-single already ships this dep today).

---

## File structure

```
kubernetes/utility/apps/observability/victoria-logs-collector/
  flux-sync.yaml                # child Flux Kustomization (sops label — consumes a Secret)
  app/
    kustomization.yaml          # lists: oci-repository, helm-release
    oci-repository.yaml         # OCIRepository, tag 0.3.8
    helm-release.yaml           # HelmRelease `victoria-logs-collector`, chartRef, driftDetection
    network-policy.yaml         # collector egress: vmauth:8427 + K8s API 443
```

Modify:

- `kubernetes/utility/apps/observability/kustomization.yaml` — add
  `  - ./victoria-logs-collector/flux-sync.yaml` (+ `dependsOn: [victoria-auth]` lives in the flux-sync).
- `kubernetes/utility/apps/observability/victoria-auth/app/network-policy.yaml` — second
  ingress rule for the collector (below).
- `kubernetes/utility/apps/observability/victoria-logs/app/README.md` — "Shippers deployed"
  note: utility unit now covered by victoria-logs-collector.

App name `victoria-logs-collector` (app-template-style short names, like `victoria-auth`). All files get
the repo's `---` + `# yaml-language-server: $schema=...` first lines; use the schema URLs copied
from the victoria-logs app files verbatim.

---

## Task 1 — App tree + HelmRelease

**`app/oci-repository.yaml`** (same shape as victoria-logs' one):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: victoria-logs-collector
spec:
  interval: 30m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  url: oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-collector
  ref:
    tag: 0.3.8
```

**`app/helm-release.yaml`** — HelmRelease `victoria-logs-collector`, chartRef OCIRepository `victoria-logs-collector`,
same install/upgrade/remediation + `driftDetection: mode: enabled` block as
`victoria-logs/app/helm-release.yaml`. Values:

```yaml
values:
  image:
    tag: v1.53.0
  env:
    - name: VL_TOKEN
      valueFrom:
        secretKeyRef:
          name: vmauth-tokens
          key: VMAUTH_TOKEN_UTILITY
  remoteWrite:
    - url: >-
        http://vmauth.observability.svc.cluster.local:8427/insert/jsonline?_stream_fields=kubernetes.pod_namespace,kubernetes.pod_name,kubernetes.container_name&_msg_field=message
      format: jsonline
      maxDiskUsagePerURL: 1Gi
      headers:
        Authorization: Bearer %{VL_TOKEN}
  collector:
    extraFields: '{"cluster":"utility"}'
    excludeFilter: kubernetes.pod_name:=%{HOSTNAME}
  podAnnotations:
    reloader.stakater.com/auto: "true"
  podMonitor:
    enabled: true
    vm: false   # utility runs kube-prometheus-stack, not VM-operator
  resources:
    requests: {cpu: 50m, memory: 64Mi}
    limits: {memory: 256Mi}
```

Notes for the implementer:

- `%{HOSTNAME}` resolves from the container's own env (downward-API NOT needed — HOSTNAME is set
  by the runtime). If the excludeFilter turns out not to expand env, fall back to static
  `kubernetes.pod_name:="victoria-logs-collector-..."` via a `fieldRef` env + check the rendered DaemonSet
  (`flux --dry-run` render or live `-o yaml`).
- Stream fields are assigned endpoint-side via the URL query params above; `msgField`/`streamFields`
  agent-side config is left at chart defaults (they matter for the `native` format, jsonline +
  query params is the path we verified).
- `includePodLabels` defaults to true in the chart — keep it (pod labels become
  `kubernetes_labels_*` fields).
- SecurityContext: keep chart defaults (runs as root; needs read on root-owned log files, write
  on `/var/lib/vl-collector`).

**`flux-sync.yaml`**: copy `victoria-logs/flux-sync.yaml`, rename to `victoria-logs-collector`, keep the
`sops.flux.home.arpa/enabled: "true"` label, add `dependsOn: [{name: victoria-auth}]` so the
collector never lands before the front door + tokens.

**`app/kustomization.yaml`**: `oci-repository.yaml`, `helm-release.yaml`, `network-policy.yaml`.

**Registration**: append `./victoria-logs-collector/flux-sync.yaml` to the observability namespace
kustomization.

Validate: `kubectl kustomize kubernetes/utility/apps/observability/victoria-logs-collector/app` builds;
`flux build kustomization` dry-run of the tree; then
`helm template oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-collector --version 0.3.8`
locally and eyeball: DaemonSet mounts `/var/log` + `/var/lib` ro, data hostPath
`/var/lib/vl-collector`, flags contain `-remoteWrite.url=...` and `-remoteWrite.headers=` with
`Authorization:Bearer %{VL_TOKEN}`.

Commit: `feat(vmlogs): deploy victoria-logs-collector shipper on utility cluster`

## Task 2 — NetworkPolicy wiring

Two edits (one new file, one patch):

1. **New** `victoria-logs-collector/app/network-policy.yaml` — egress netpol for the collector (utility ns
   likely has a default-deny or at least follows the repo's explicit-policy style):

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: victoria-logs-collector
   spec:
     podSelector:
       matchLabels:
         app.kubernetes.io/name: victoria-logs-collector   # verify rendered pod labels first
     policyTypes: [Egress]
     egress:
       - to:
           - podSelector:
               matchLabels:
                 app.kubernetes.io/name: vmauth
         ports: [{protocol: TCP, port: 8427}]
       - to:
           - namespaceSelector:
               matchLabels:
                 kubernetes.io/metadata.name: kube-system
         ports: [{protocol: TCP, port: 443}]   # K8s API enrichment
       - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]   # cluster DNS
   ```

   (Verify the exact pod labels from `helm template` render before writing the selector; the
   chart's pod labels are `app.kubernetes.io/name: victoria-logs-collector` + instance/component
   — copy from the render. DNS rule targets whatever the repo's other netpol style uses —
   check `victoria-auth`/opengist for the convention; if utility ns has no default-deny
   egress, ship ingress-only rules and note it.)

2. **Patch** `victoria-auth/app/network-policy.yaml` — the vmauth netpol is allow-only, so
   add a second source allowing the collector (same-namespace, specific pod label):

   ```yaml
       - from:
           - podSelector:
               matchLabels:
                 app.kubernetes.io/name: victoria-logs-collector
         ports:
           - protocol: TCP
             port: 8427
   ```

Commit: `feat(vmlogs): allow victoria-logs-collector through vmauth network policy`

## Task 3 — Docs + lint

- Patch `victoria-logs/app/README.md`: shipper status — utility unit covered by
  `victoria-logs-collector` (vlagent v1.53.0, disk buffer at `/var/lib/vl-collector`,
  `cluster="utility"` label); main/NAS/bifrost/workstations still pending.
- ADR 0016 open-question 3 resolves to *victoria-logs-collector on Talos nodes* — record it
  in the same commit: add a note under the open questions (status flip to `accepted` stays the
  post-deploy follow-up commit as phase 1 did).
- `task lint:yaml`, `task lint:prettier` (fix: `task lint:prettier:fix`).

Commit: `docs(vmlogs): record utility victoria-logs-collector rollout`

## Task 4 — Push + PR (coordinator)

Branch `feature/victoria-logs-collector-utility` (≤40 chars, kebab). PR body: numbered STEV-style
summary + local evidence (helm template render, kustomize build) + post-merge checklist below.
Never merge ourselves; merge is `task git:pr-merge` on explicit go-ahead.

## Post-merge live verification (readonly@utility only)

```bash
K="kubectl --context readonly@utility -n observability"
$K get pods -l app.kubernetes.io/name=victoria-logs-collector -o wide   # Ready on util01
$K get helmrelease victoria-logs-collector -o jsonpath='{.status.conditions}'      # Ready=True
# 1) fresh logs visible (read token):
T=$($K get secret vmauth-tokens -o "jsonpath={.data.VMAUTH_TOKEN_GRAFANA}" | base64 -d)
curl -s -H "Authorization: Bearer ***" \
  'https://logs.techtales.io/select/logsql/query?query=%7Bcluster%3D%22utility%22%7D&limit=5'
#    → lines from real pods, labels host=util01, kubernetes.* fields present
# 2) buffer dir created + checkpoint file:
$K exec ds/victoria-logs-collector-... -- ls /var/lib/vl-collector   (readonly may block exec →
#    check via node: ssh util01 ls /var/lib/vl-collector, or skip; vlagent metrics prove drain)
# 3) metrics: $K get --raw "/api/v1/namespaces/observability/pods/<pod>:9429/proxy/metrics" \
#    | grep -E "vlagent_(remotewrite_rows|disk_cache)"   → rows buffered==0 once caught up
# 4) restart tolerance: kubectl rollout restart ds is not possible read-only — verify
#    indirectly: delete one vmauth pod (needs perms) OR just confirm no data gap across the
#    Flux rollout of the collector itself (query window spanning the pod restart).
```

Also: confirm the collector's **own** logs are absent (`{kubernetes_pod_name=~"victoria-logs-collector.*"}`
→ empty). Add one Alertmanager-friendly check note: watch
`vlagent_remotewrite_bytes_pending` later if we wire a rule (out of scope here).

## Risks / gotchas (verified, pinned)

- **vmauth netpol is allow-only** — forgot the Task 2 patch → collector runs Ready but every
  push blackholes (TCP timeout, buffer grows silently). The metrics check above catches it.
- **Token rotation** rotates ALL keys of `vmauth-tokens` → reloader restarts the collector pod
  too (annotation set); expected, harmless.
- **No multi-line merging** in vlagent v1.53.0: Java/Python stack traces arrive as separate
  lines. Accepted at lab scale; query-side fix if it ever hurts.
- **Label enrichment not hot-refreshed**: after changing pod/node labels, `rollout restart` the
  DaemonSet.
- **storage class irrelevant**: the collector uses hostPaths, no PVC → nothing to wait for, no
  StorageClass decision.
- Chart dep `victoria-metrics-common` is OCI-pulled at render time — first reconcile may lag
  a few minutes fetching it (same as victoria-logs, observed).
- If `excludeFilter` env expansion misbehaves, the loop is visible immediately: VL query
  `{kubernetes_pod_name=~"victoria-logs-collector.*"}` exploding in volume. Fix = static pod-name filter.
