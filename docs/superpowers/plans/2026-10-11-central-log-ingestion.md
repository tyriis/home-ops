# Central Log Ingestion (VictoriaLogs + vmauth) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy VictoriaLogs single-node behind vmauth with per-unit bearer tokens on the utility cluster (ADR 0016 Option C, phase 1, utility-side only).

**Architecture:** `victoria-logs` HelmRelease (victoria-logs-single chart) + plain `vmauth` Deployment/Service/ConfigMap in the existing `observability` namespace. HTTPRoute `logs.techtales.io` on the existing Envoy Gateway. Seven Sops secrets (6 unit write tokens + 1 Grafana read token) feed vmauth env vars, referenced via `%{ENV_VAR}` placeholders in `vmauth.yaml`. NetworkPolicy locks VL:9428 to vmauth only.

**Tech Stack:** Flux (Kustomization/HelmRelease/HelmRepository), victoria-logs-single chart 0.13.10 (VL v1.53.0), vmauth v1.153.0, Sops+age (public key), Envoy Gateway, kustomize.

**Spec:** `docs/superpowers/specs/2026-10-11-central-log-ingestion-design.md`

## Global Constraints

- App tree: `kubernetes/utility/apps/observability/victoria-logs/` (`flux-sync.yaml` + `app/*.yaml`), registered in `kubernetes/utility/apps/observability/kustomization.yaml`.
- Every YAML gets the repo's `# yaml-language-server: $schema=...` first-line comment (copy the schema URL style from `kubernetes/utility/apps/git-system/opengist/app/*.yaml`).
- Secret files: 7 **separate** `Secret`s, one per unit, Sops-encrypted (`sops -e -i`), `stringData.token` key. Encrypted with the age recipient from `.sops.yaml` rule `kubernetes/utility/.*` (`age1clg0rd6ca86h3lnfnjyqsc9stgr0cnyp3l5uswtusxppjq9h2vcsaqckec`).
- Commits: `<type>(vmlogs): <imperative ≤72 chars>`.
- VL is NOT directly routable: no HTTPRoute for VL; only vmauth reaches VL:9428.
- vmauth token injection via `%{VAR}` placeholders in the auth config (docs-verified) fed by `envFrom`-free individual `secretKeyRef` env entries.
- Hot-reload: `-configCheckInterval=1m` (vmauth default 0 = disabled, verified in v1.153.0 flag help).
- Repo lint must pass: `task lint:yaml` and `task lint:prettier` (or `task pre-commit`).

## Facts this plan bakes in (verified 2026-10-11)

- Rendered VL objects (chart 0.13.10, release `victoria-logs`, ns `observability`): Service **`victoria-logs-victoria-logs-single-server`** (port 9428), StatefulSet pods labeled **`app.kubernetes.io/name: victoria-logs-single`**, PVC from volumeClaimTemplate → pod name `victoria-logs-victoria-logs-single-server-0`.
- VL single-node insert path: `POST /insert/jsonline` (tenant via headers only; `/insert/<t>/jsonline` does NOT route on single-node) → src_paths lock `/insert/.*` covers it.
- Grafana plugin (`victoriametrics-logs-datasource` v0.32.0) calls `/select/logsql/*` → read user lock `/select/.*` + `/api/v1/.*`; vmui is at `/select/vmui/` (covered by `/select/.*`).
- vmauth: bad/unknown token → **401**; authenticated user, no matching route → **400** (not 403); `deny_paths` (v1.152.0+) → **403**. We add a deny catch-all per user so denied paths are 403.
- Envoy data plane: Deployment `envoy` in ns `networking` (NetworkPolicy source selector); Gateway `envoy` ns `networking` sectionName `https`; wildcard cert covers `logs.techtales.io`.

## File Structure

Create under `kubernetes/utility/apps/observability/victoria-logs/`:

```
flux-sync.yaml                     # child Flux Kustomization (sops-labeled)
app/kustomization.yaml             # lists all app resources
app/helm-repository.yaml           # HelmRepository victoria-metrics-charts
app/helm-release.yaml              # victoria-logs HelmRelease (chart 0.13.10)
app/vmauth-configmap.yaml          # vmauth.yaml incl. graduation comment block
app/vmauth-deployment.yaml         # vmauth Deployment
app/vmauth-service.yaml            # vmauth Service :8427
app/network-policy.yaml            # VL ingress-from-vmauth + vmauth ingress-from-envoy-dataplane
app/http-route.yaml                # logs.techtales.io
app/secrets/vmauth-token-{ms01,utility,nas,bifrost,workstation,remote,grafana}.sops.yaml
app/README.md                      # tokens table, URLs, curl per unit, Grafana DS, graduation triggers
```

Modify: `kubernetes/utility/apps/observability/kustomization.yaml` (one resources line).
Modify: `docs/decisions/0016-central-log-platform-victorialogs-on-utility.md` (status→accepted) — **post-deploy follow-up commit, not in the initial PR**.

---

### Task 1: App tree, Flux wiring, HelmRelease

**Files:**
- Create: `kubernetes/utility/apps/observability/victoria-logs/flux-sync.yaml`
- Create: `kubernetes/utility/apps/observability/victoria-logs/app/kustomization.yaml`
- Create: `kubernetes/utility/apps/observability/victoria-logs/app/helm-repository.yaml`
- Create: `kubernetes/utility/apps/observability/victoria-logs/app/helm-release.yaml`
- Modify: `kubernetes/utility/apps/observability/kustomization.yaml` (append `  - ./victoria-logs/flux-sync.yaml` to `resources:`)

**Interfaces:**
- Produces: HelmRelease `victoria-logs` → Service `victoria-logs-victoria-logs-single-server:9428`, pods labeled `app.kubernetes.io/name: victoria-logs-single` (consumed by Tasks 2/4).

- [ ] **Step 1: Write `app/helm-repository.yaml`** (schema comment: `https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/helmrepository_v1.json`)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: victoria-metrics-charts
spec:
  interval: 1h
  timeout: 3m
  url: https://victoriametrics.github.io/helm-charts/
```

- [ ] **Step 2: Write `app/helm-release.yaml`** (schema comment: `https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json`)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: victoria-logs
spec:
  interval: 30m
  driftDetection:
    mode: enabled
  chart:
    spec:
      chart: victoria-logs-single
      version: 0.13.10
      sourceRef:
        kind: HelmRepository
        name: victoria-metrics-charts
        namespace: observability
      interval: 1h
  install:
    remediation:
      retries: -1
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  uninstall:
    keepHistory: false
  values:
    server:
      replicaCount: 1
      retentionPeriod: 30d
      image:
        tag: v1.53.0
      persistentVolume:
        enabled: true
        size: 20Gi
        storageClassName: local-nvme
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
```

- [ ] **Step 3: Write `flux-sync.yaml`** (schema comment + structure copied from `kubernetes/utility/apps/observability/kube-prometheus-stack/flux-sync.yaml`)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app victoria-logs
  labels:
    sops.flux.home.arpa/enabled: "true"
spec:
  targetNamespace: observability
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/utility/apps/observability/victoria-logs/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

- [ ] **Step 4: Write `app/kustomization.yaml`** listing: `./helm-repository.yaml`, `./helm-release.yaml`, `./vmauth-configmap.yaml`, `./vmauth-deployment.yaml`, `./vmauth-service.yaml`, `./network-policy.yaml`, `./http-route.yaml`, and the 7 `./secrets/*.sops.yaml` files (add the vmauth/secrets entries in later tasks — until then keep only existing files listed so kustomize never references a missing path; simplest: write kustomization LAST in task 5).

- [ ] **Step 5: Register in the namespace kustomization** — append the resources line shown above.

- [ ] **Step 6: Validate**

Run: `kustomize build kubernetes/utility/apps/observability/victoria-logs/app` (or `flux build kustomization . --dry-run` / `kubectl kustomize`). If `kustomize` is absent, run `mise exec -- flux build kustomization victoria-logs ./kubernetes/utility/apps/observability/victoria-logs/app --dry-run`.
Expected: builds clean, contains HelmRelease + HelmRepository.

- [ ] **Step 7: Commit** — `feat(vmlogs): add VictoriaLogs single-node HelmRelease on utility`

### Task 2: vmauth (ConfigMap, Deployment, Service)

**Files:**
- Create: `.../app/vmauth-configmap.yaml`, `.../app/vmauth-deployment.yaml`, `.../app/vmauth-service.yaml`

**Interfaces:**
- Consumes: VL Service name `victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428` (Task 1); Secrets `vmauth-token-<unit>` key `token` (Task 3 — env-only references, no file dependency).
- Produces: pods labeled `app.kubernetes.io/name: vmauth`, Service `vmauth` port 8427 (consumed by Tasks 4/5).

- [ ] **Step 1: Write `vmauth-configmap.yaml`** — ConfigMap `vmauth`, key `vmauth.yaml`:

```yaml
users:
  # ---- write users: /insert/.* only, 403 on everything else ----
  - name: ms01
    bearer_token: "%{VMAUTH_TOKEN_MS01}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

  - name: utility
    bearer_token: "%{VMAUTH_TOKEN_UTILITY}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

  - name: nas
    bearer_token: "%{VMAUTH_TOKEN_NAS}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

  - name: bifrost
    bearer_token: "%{VMAUTH_TOKEN_BIFROST}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

  - name: workstation
    bearer_token: "%{VMAUTH_TOKEN_WORKSTATION}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

  - name: remote
    bearer_token: "%{VMAUTH_TOKEN_REMOTE}"
    url_map:
      - src_paths: ["/insert/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/*"]
        deny_paths: ["/.*"]

  # ---- read user: Grafana victoriametrics-logs-datasource + vmui ----
  - name: grafana-readonly
    bearer_token: "%{VMAUTH_TOKEN_GRAFANA}"
    url_map:
      - src_paths: ["/select/.*", "/api/v1/.*"]
        url_prefix: "http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428"
      - src_paths: ["/.*"]
        deny_paths: ["/.*"]

# NOTE: no `unauthorized_user:` block — requests with an unknown token get 401,
# they are never proxied.

# ---- GRADUATION BLOCK (do not enable yet) --------------------------------
# Phase 2/3 changes are vmauth-config-only:
#
# 1) Metrics backend on the same front door (ADR 0016 consequences):
#    add a vm-single/vm-cluster HelmRelease, then one user per unit like:
#      - name: ms01-metrics
#        bearer_token: "%{VMAUTH_TOKEN_MS01_METRICS}"
#        url_map:
#          - src_paths: ["/api/v1/write"]
#            url_prefix: "http://victoria-metrics.observability.svc.cluster.local:8428"
#          - src_paths: ["/api/v1/query.*", "/api/v1/series.*", "/api/v1/labels.*"]
#            url_prefix: "http://victoria-metrics.observability.svc.cluster.local:8428"
#
# 2) Option B (vlcluster) tenant rewrite — per-unit hard tenancy:
#    swap VL for vlinsert/vmselect and rewrite tenant per user via headers:
#      - name: ms01
#        bearer_token: "%{VMAUTH_TOKEN_MS01}"
#        url_map:
#          - src_paths: ["/insert/.*"]
#            url_prefix: "http://vlinsert.observability.svc.cluster.local:9491/insert/1"
#            headers: ["AccountID: 1", "ProjectID: 0"]
#    (Grafana source swap = datasource URL change only.)
# --------------------------------------------------------------------------
```

- [ ] **Step 2: Write `vmauth-deployment.yaml`** — Deployment `vmauth`, replicas 1:
  - container image `docker.io/victoriametrics/vmauth:v1.153.0`
  - args exactly: `["-auth.config=/etc/vmauth/vmauth.yaml", "-httpListenAddr=:8427", "-configCheckInterval=1m"]` (`%{VAR}` placeholders in the config are substituted by vmauth from its own container env — docs-verified: "The config may contain `%{ENV_VAR}` placeholders, which are substituted by the corresponding `ENV_VAR` environment variable values")
  - 7 env entries, pattern:

```yaml
    env:
      - name: VMAUTH_TOKEN_MS01
        valueFrom:
          secretKeyRef:
            name: vmauth-token-ms01
            key: token
```
  (repeat for `VMAUTH_TOKEN_UTILITY`/`vmauth-token-utility`, `VMAUTH_TOKEN_NAS`/`vmauth-token-nas`, `VMAUTH_TOKEN_BIFROST`/`vmauth-token-bifrost`, `VMAUTH_TOKEN_WORKSTATION`/`vmauth-token-workstation`, `VMAUTH_TOKEN_REMOTE`/`vmauth-token-remote`, `VMAUTH_TOKEN_GRAFANA`/`vmauth-token-grafana`)
  - volume `config`: configMap `vmauth`, mounted at `/etc/vmauth` (readOnly)
  - `containerPort: 8427` name `http`
  - readinessProbe+livenessProbe `httpGet: {path: /metrics, port: 8427}`
  - resources: requests `cpu: 25m`, `memory: 64Mi`; limits `memory: 256Mi`
  - securityContext pod-level: `runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534`
  - labels on pod template: `app.kubernetes.io/name: vmauth`, `app.kubernetes.io/component: proxy`
  - annotations: `reloader.stakater.com/auto: "true"` (repo already uses this pattern in opengist)

- [ ] **Step 3: Write `vmauth-service.yaml`** — Service `vmauth`, port 8427 name `http`, selector `app.kubernetes.io/name: vmauth`.

- [ ] **Step 4: Validate** — vmauth config parses: `docker run --rm -v $PWD/kubernetes/utility/apps/observability/victoria-logs/app:/c:ro docker.io/victoriametrics/vmauth:v1.153.0 -auth.config=/c/vmauth.yaml -configCheckInterval=0 -dryRun 2>&1 || true` — vmauth has **no** `-dryRun`; instead start it with dummy env and grep for `INFO` config-loaded line:
  `docker run --rm -e VMAUTH_TOKEN_MS01=a -e VMAUTH_TOKEN_UTILITY=b -e VMAUTH_TOKEN_NAS=c -e VMAUTH_TOKEN_BIFROST=d -e VMAUTH_TOKEN_WORKSTATION=e -e VMAUTH_TOKEN_REMOTE=f -e VMAUTH_TOKEN_GRAFANA=g -v $PWD/.../app:/c:ro docker.io/victoriametrics/vmauth:v1.153.0 -auth.config=/c/vmauth.yaml` — expect it to start listening (then Ctrl-C / use `timeout 5`).
  If docker is unavailable, skip — the smoke tests after deploy prove it.

- [ ] **Step 5: Commit** — `feat(vmlogs): front VictoriaLogs with vmauth per-unit tokens`

### Task 3: Unit tokens (7 Sops secrets)

**Files:**
- Create: `.../app/secrets/vmauth-token-{ms01,utility,nas,bifrost,workstation,remote,grafana}.sops.yaml`

- [ ] **Step 1: Generate + write plaintext** — for each unit in the list: `openssl rand -hex 32`, write a plaintext Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vmauth-token-ms01
stringData:
  token: <64-hex>
```

- [ ] **Step 2: Encrypt in place** — `sops -e -i <file>` (age public key from `.sops.yaml` rule is enough; no private key needed). Note the vmauth Deployment references key `token` — do not rename.

- [ ] **Step 3: Verify** — `sops fileinfo <file>` shows the `age1clg0rd6ca86...` recipient and `encrypted_regex ^(data|stringData)$`. `grep -r 'token: ENC\[' ... | wc -l` → 7. No plaintext token anywhere: `grep -l "$(the generated hex)" -r kubernetes/` → empty.

- [ ] **Step 4: Commit** — `feat(vmlogs): add per-unit vmauth token secrets`

### Task 4: NetworkPolicy + HTTPRoute

**Files:**
- Create: `.../app/network-policy.yaml`, `.../app/http-route.yaml`

- [ ] **Step 1: `network-policy.yaml`** — two policies (schema comment copied from `kubernetes/main/apps/ai/searxng/app/network-policy.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: victoria-logs
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: victoria-logs-single
  policyTypes: [Ingress]
  ingress:
    # only vmauth may reach VL
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: vmauth
      ports:
        - protocol: TCP
          port: 9428
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vmauth
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vmauth
  policyTypes: [Ingress]
  ingress:
    # Envoy Gateway data plane (deployment `envoy` in ns networking) + same-namespace clients (Grafana plugin if colocated later)
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: networking
      ports:
        - protocol: TCP
          port: 8427
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8427
```

- [ ] **Step 2: `http-route.yaml`** — HTTPRoute `vmauth`, metadata.annotations `external-dns/unifi: "true"`, spec copied from `kubernetes/utility/apps/git-system/opengist/app/http-route.yaml` with: hostnames `[logs.techtales.io]`, parentRefs `[{name: envoy, namespace: networking, sectionName: https}]`, rules → backendRefs `[{name: vmauth, port: 8427}]`.

- [ ] **Step 3: Validate** — kustomize build the app dir again (now with vmauth + netpol + route).

- [ ] **Step 4: Commit** — `feat(vmlogs): restrict VL access and expose logs.techtales.io`

### Task 5: README + final kustomization + lint

**Files:**
- Create: `.../app/README.md`
- Modify: `.../app/kustomization.yaml` (ensure it lists exactly: helm-repository, helm-release, vmauth-configmap, vmauth-deployment, vmauth-service, network-policy, http-route, secrets/*.sops.yaml ×7)

- [ ] **Step 1: README** must contain:
  - Unit → secret-name table (7 rows).
  - Insert URL per path: LAN `https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg`; Tailscale: same hostname (resolves LAN IP via tunnel).
  - Per-unit curl example (jsonline, one line each, token from `kubectl -n observability get secret vmauth-token-<unit> -o jsonpath='{.data.token}' | base64 -d`).
  - Grafana datasource: type Victoria Logs (victoriametrics-logs-datasource), URL `https://logs.techtales.io`, custom HTTP header `Authorization: Bearer <grafana token>`; example LogsQL `{cluster="utility"}`.
  - vmui: `https://logs.techtales.io/select/vmui/` (read token).
  - Verification transcript section (filled from post-deploy evidence — placeholder `_(filled after deploy)_` allowed here only).
  - Graduation triggers copied from the ADR (tenant isolation / per-unit retention / ingest scale).

- [ ] **Step 2: Lint** — `task lint:yaml` and `task lint:prettier`; fix findings.

- [ ] **Step 3: Commit** — `feat(vmlogs): document log ingestion app and shipper wiring`

### Task 6: Push + PR request (coordinator, not an agent task)

- [ ] `git push -u origin feature/vmlogs-central-ingestion`
- [ ] Ask to open PR (base `main`). Never merge ourselves. PR body: app summary + local evidence (kustomize build output, vmauth config parse) + **post-merge live verification checklist below**.
- [ ] Post-merge (after Flux reconciles): run live checks, paste outputs into PR thread / follow-up commit:
  - `kubectl --context readonly@utility -n observability get pods,pvc,helmrelease,helmrepository,httproute`
  - 204 insert, 401 bad token, 403 write-token-on-select, 403 read-token-on-insert, query-back, vmui reachable.
  - Then follow-up commit on a new branch: `docs(vmlogs): accept ADR 0016, record resolved storage/exposure decisions` (flip `status: proposed`→`accepted`, add note).

## Post-merge live verification (exact commands)

```bash
K="kubectl --context readonly@utility -n observability"
$K get pods,pvc,helmrelease
T=$(sops -d --extract '["stringData"]["token"]' kubernetes/utility/apps/observability/victoria-logs/app/secrets/vmauth-token-utility.sops.yaml) # or kubectl get secret + base64 -d
# 1) insert → 204
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H "Authorization: Bearer $T" \
  --data-binary '{"msg":"smoke","host":"test","cluster":"utility","unit":"utility","_time":"'"$(date +%s%N)"'"}' \
  'https://logs.techtales.io/insert/jsonline?_stream_fields=host,cluster,unit&_msg_field=msg&_time_field=_time'
# 2) wrong token → 401        (same curl, -H "Authorization: Bearer deadbeef")
# 3) write token on query → 403 (write T against /select/logsql/query?query=*)
# 4) read token: query back → line with labels host="test" cluster="utility"
R=$(... vmauth-token-grafana ...)
curl -s -H "Authorization: Bearer $R" 'https://logs.techtales.io/select/logsql/query?query={host%3D"test"}'
# 5) vmui: curl -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $R" https://logs.techtales.io/select/vmui/ → 200
```

## Review Focus

- **Tenant/path mismatch**: single-node VL ignores `/insert/<t>/` paths — our lock is `/insert/.*` on plain paths; a shipper POSTing `/insert/0/jsonline` gets proxied but VL 404s → shipper docs must use `/insert/jsonline`. Pinned in README examples (Task 5).
- **400 vs 403 on denied paths**: without the per-user deny catch-all, path denial returns 400 and the verification step expecting 403 fails. Pinned by Task 2 catch-all + Task 6 check 3/4.
- **`%{ENV}` typo** in vmauth.yaml = config-load failure at startup (Deployment never Ready, Flux `wait: true` surfaces it in CI-ish reconcile). Pinned by Task 2 Step 4 parse check.
- **Secret key drift**: vmauth Deployment references key `token` — Task 3 Step 2 locks the key name.
- **local-nvme WaitForFirstConsumer**: PVC stays Pending until VL pod schedules — expected, not a failure. Noted in Task 6 checklist.
- **Namespace kustomization edit** breaking the existing `observability` tree — validated by kustomize build of `kubernetes/utility/apps/observability` in Task 1 Step 6.
