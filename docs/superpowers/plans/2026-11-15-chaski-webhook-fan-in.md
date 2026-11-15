# chaski Webhook Fan-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put one public GitHub webhook entry point (`github-hooks.techtales.io`) on the main cluster, relaying each delivery to its existing consumer in-cluster, without touching any consumer's webhook secret.

**Architecture:** chaski 0.5.4 runs in `networking` on main as a Flux `HelmRelease` from `oci://ghcr.io/home-operations/charts/chaski`. Routes and targets are committed YAML that contains only `{{ env "…" }}` references; the values behind them come from an `ExternalSecret` reading each consumer's *existing* OpenBao key. Each route verifies the inbound GitHub signature with the consumer's own secret and forwards the body **verbatim** plus the original signature headers, so the consumer's own validation keeps working unchanged. GitHub-side migration is a payload-URL edit per webhook — secret, events and consumer config stay as they are. Rollback is the reverse URL edit.

**Tech Stack:** chaski 0.5.4 (AGPL-3.0), Flux `HelmRelease`/`OCIRepository` (helm.toolkit.fluxcd.io/v2, source.toolkit.fluxcd.io/v1), Gateway API `HTTPRoute`, cloudflared tunnel, External Secrets Operator → OpenBao (`ClusterSecretStore/openbao-backend`), VictoriaMetrics operator (`VMServiceScrape`, `VMRule`), Gatus.

**Spec:** https://github.com/tyriis/home-ops/issues/11724 (the fact-finding pass is the spec; its "Not decided" list is resolved in `## Resolved decisions` below)

## Global Constraints

- **chaski cannot re-sign.** No outbound signing exists (`verify` is inbound-only, the funcmap has no keyed hash, `relay.Input.RawBody` is never projected into templates). Therefore: `message` MUST stay unset on every relay route (that is what makes the body byte-verbatim), and the consumer's validating secret MUST equal the route's `verify.github.secret`.
- **Only configured headers are forwarded.** Every route must declare the headers its target validates; inbound names are lower-cased for templates (`{{ index .headers "x-hub-signature-256" }}`).
- `POST /hooks/{route}` is an exact path — no suffix passthrough. The target URL carries the consumer's own path (`/events`, `/hook/<hash>`, `/webhook/<path>`).
- **The repo is public.** No secret literal may appear in `helm-release.yaml`, a ConfigMap, or committed values. Route secrets use `{{ env "VAR" }}` only; the loader renders `verify.secret` from the process environment (verified: `internal/config/routes.go` → `Verify.Secrets()` is env-rendered in place).
- One instance, one cluster: chaski lives on **main** (12 of 13 live endpoints are main-side; the only tunnel in the estate is main's). Cross-cluster reach, if ever needed, is hostname-HTTPS over the public/CC edge — never Service DNS.
- Versions pinned in `OCIRepository.spec.ref.tag`; Renovate reads that field. No central version file.
- Commit messages via the `git-commit` skill: `type(scope): description`, imperative, ≤72 chars. Branch: `feature/chaski-webhook-fan-in`.
- `gh` is not available on this machine. GitHub-side changes (webhook URLs) are manual UI edits, or done through the deployed GitHub MCP server — never `gh`.
- Verify with `task flate:test -- main`, `task flate:diff -- main`, `task deadvalues:check-values`, `task lint:yaml`. Never `kubectl apply`; everything lands through Flux.

## Review Focus

1. **Body and header integrity.** A route that sets `message`, or omits `X-Hub-Signature-256` / `X-GitHub-Event` passthrough, produces a downstream 401 that looks like "GitHub is broken". Every relay route is proven with `?dryRun=1` and one real redelivery before the next consumer moves.
2. **Retries against non-idempotent targets.** Global default is 3 attempts on 5xx/transport error. Atlantis plan/apply is not idempotent — those targets set `retry.attempts: 1` and forward `X-GitHub-Delivery` so a duplicate can be recognised downstream.
3. **Silent delivery failure.** chaski answers GitHub `200` once the relay succeeds; a target that later fails is only visible in `chaski_target_sends_total` / `chaski_relays_total`. Without the alerts in Task 7 a broken Atlantis relay would go unnoticed until someone misses a plan comment.
4. **Self-inflicted SPOF.** One chaski pod in front of all GitHub-triggered deploys, while the GitRepository poll interval is **2h** on both clusters. `replicaCount` is 2 with a PDB from the start, and the 2h poll is the documented worst case, not a surprise.
5. **Path coupling on flux.** A `type: github` Receiver's path is `sha256(token+name+namespace)`; the chaski target URL encodes it. Token rotation silently moves the flux URL — the route carries the coupling comment, and flux migration is a gated phase, not v1.
6. **Atlantis host drift.** `cloudflared/app/resources/config.yaml` already carries a stale `atlantic-techtales-io-terraform-opnsense` entry and a duplicated `kromgo` host. The cleanup task must remove exactly what it enumerates, and must not "tidy" anything else.

---

## Resolved decisions

| Issue's open question | Resolution in this plan |
|---|---|
| 1. shared secret per consumer vs per-hop | **Shared secret per consumer** (i.e. route secret == consumer secret). No consumer secret changes, no OpenBao rotation, per-consumer rollback. Per-hop needs an upstream feature; revisit only if a consumer's secret must differ from the inbound one. |
| 2. doco-cd in or out | **Out of v1**, in as a gated phase (Task 9). Enabling webhooks reverses polling practice and needs the docker-host inventory, which is a separate decision. |
| 3. flux via chaski or direct | **Direct in v1**, gated phase (Task 8). Gain is nil (flux already validates and is already on one host), and the token-derived path is real coupling in the critical reconcile path. |
| 4. where chaski runs | **main, namespace `networking`**, LB-internal Service, one public hostname through the existing tunnel. Matches where 12 of 13 endpoints live and where the only tunnel is. |

**v1 scope:** Atlantis (10 instances → 1 public host), plus the relay platform, observability and the tunnel cleanup. flux, n8n and doco-cd are explicitly gated phases with their own decision.

**Why Atlantis first:** it is 10 of the 13 public webhook hosts, each with its own certificate-less `<release>-webhook.techtales.io` tunnel entry, its own `external-dns` records and its own Gatus probe. Collapsing them to one host is the entire measurable win; flux and n8n are single hosts whose migration buys nothing but risk.

## File structure

**Create**

| Path | Responsibility |
|---|---|
| `kubernetes/main/apps/networking/chaski/flux-sync.yaml` | Flux Kustomization → `.../chaski/app`, `dependsOn: external-secrets-stores` |
| `kubernetes/main/apps/networking/chaski/app/kustomization.yaml` | resource list |
| `kubernetes/main/apps/networking/chaski/app/oci-repository.yaml` | `oci://ghcr.io/home-operations/charts/chaski`, `ref.tag: 0.5.4` |
| `kubernetes/main/apps/networking/chaski/app/helm-release.yaml` | chartRef HelmRelease; `config.routes`/`config.targets` (only env references), HA, resources, init-container `chaski validate` gate |
| `kubernetes/main/apps/networking/chaski/app/external-secret.yaml` | one Secret keyed by consumer (`data:` + `remoteRef.property`), from each consumer's **existing** OpenBao path |
| `kubernetes/main/apps/networking/chaski/app/http-route.yaml` | `github-hooks.techtales.io`, `PathPrefix: /hooks/`, envoy https listener, external-dns cloudflare+unifi, Gatus 404 probe |
| `kubernetes/main/apps/networking/chaski/app/vm-service-scrape.yaml` | scrape `metrics:8081` |
| `kubernetes/main/apps/networking/chaski/app/vm-rule.yaml` | relay/target failure alerts |
| `docs/decisions/0026-webhook-fan-in-via-chaski.md` | ADR: why one entry point, why passthrough not re-signing, why Atlantis-only in v1 |

**Modify**

| Path | Change |
|---|---|
| `kubernetes/main/apps/networking/kustomization.yaml` | add `./chaski/flux-sync.yaml` |
| `kubernetes/main/apps/networking/cloudflared/app/resources/config.yaml` | add `github-hooks.techtales.io`; later remove the 11 atlantis webhook entries |
| `kubernetes/components/atlantis/helm-release.yaml` | remove the `route.webhook` block (Task 6 only) |
| `kubernetes/main/apps/networking/cloudflared/README.md` (if the host table exists) | keep the manual-host list honest |

**Untouched on purpose:** every `ATLANTIS_GH_WEBHOOK_SECRET` in OpenBao, every `Receiver`, `n8n`, `doco-cd`.

---

### Task 1: ADR 0026

**Files:**
- Create: `docs/decisions/0026-webhook-fan-in-via-chaski.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the decision record Tasks 2–9 cite; `status: accepted`, `date: 2026-11-15`, `decision-makers: [tyriis]`.

- [ ] **Step 1: Write the ADR** following the `0025` template exactly (`## Context and Problem Statement`, `## Decision Drivers`, `## Considered Options`, `## Decision Outcome`, `## Consequences`, `## More Information`).

Considered options must include, at minimum: (a) status quo, 13 public endpoints; (b) chaski fan-in with header passthrough, shared secret per consumer; (c) chaski fan-in with per-hop re-signing (rejected — no upstream capability); (d) per-consumer reverse proxy such as a plain `HTTPRoute` rewrite (rejected — no fan-out, no per-route gating, still one host per consumer); (e) one org-level webhook with a single estate-wide secret (rejected — couples rotation across two orgs and every consumer).

`## Consequences` must state verbatim-grade facts: chaski is AGPL-3.0, 0.5.x, ~24 stars, no known deployment in the relay role (bus factor); it becomes a single point of failure for every GitHub-triggered flow on main; a relay outage delays reconciles by up to the 2h GitRepository poll interval.

- [ ] **Step 2: Lint**

Run: `task lint:markdown`
Expected: no errors for the new file.

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0026-webhook-fan-in-via-chaski.md
git commit -m "docs(adr): add webhook fan-in decision"
```

---

### Task 2: chaski app scaffold, no public exposure

**Files:**
- Create: `kubernetes/main/apps/networking/chaski/flux-sync.yaml`
- Create: `kubernetes/main/apps/networking/chaski/app/{kustomization,oci-repository,helm-release,external-secret}.yaml`
- Modify: `kubernetes/main/apps/networking/kustomization.yaml`

**Interfaces:**
- Consumes: `ClusterSecretStore/openbao-backend` (applied by `external-secrets-stores`, namespace `secops`).
- Produces: `Service/chaski` in `networking` with ports `http:8080` / `metrics:8081`; `Secret/chaski-secrets` whose keys become container env vars named exactly as in the table below. Task 3's routes reference those names.

- [ ] **Step 1: Scaffold `flux-sync.yaml`** exactly like `kubernetes/main/apps/flux-system/konflate/flux-sync.yaml` (yaml-language-server comment, `name: &app chaski`, `namespace: &namespace networking`, `targetNamespace: *namespace`, `path: ./kubernetes/main/apps/networking/chaski/app`, `prune: true`, `wait: true`, `interval: 30m`, `retryInterval: 1m`, `timeout: 5m`, `dependsOn: [{name: external-secrets-stores, namespace: secops}]`, `postBuild.substitute: {APP: *app, NAMESPACE: *namespace}`). Register it in `kubernetes/main/apps/networking/kustomization.yaml` next to `./cloudflared/flux-sync.yaml`.

- [ ] **Step 2: `oci-repository.yaml`** — `url: oci://ghcr.io/home-operations/charts/chaski`, `ref.tag: 0.5.4`, `interval: 30m`, `layerSelector` copy of the `konflate` file.

- [ ] **Step 3: `helm-release.yaml`** — `chartRef {kind: OCIRepository, name: chaski}`, `interval: 30m`, `driftDetection.mode: enabled`, standard remediation block, and `values:`:

  - `replicaCount: 2` (stateless), `podDisruptionBudget.enabled: true`, `podDisruptionBudget.minAvailable: 1`
  - `resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 128Mi}}`
  - `config.metricsEnabled: true`, `config.logLevel: info`, `config.logFormat: json`, `config.maxBodyBytes: 5242880`, `config.requestTimeout: 15s`
  - `monitoring.serviceMonitor.enabled: false` (repo uses `VMServiceScrape`, not Prometheus Operator)
  - `deploymentAnnotations: {reloader.stakater.com/auto: "true"}`
  - `initContainers` — one entry running `chaski validate --config /config/chaski.yaml`, so an invalid config stalls the rollout and the old pod keeps serving
  - `envFrom: [{secretRef: {name: chaski-secrets}}]`
  - `config.routes: {}` and `config.targets: {}` for this task (Task 3 fills them)

- [ ] **Step 4: `external-secret.yaml`** — `apiVersion: external-secrets.io/v1`, `refreshInterval: 5m`, `secretStoreRef {name: openbao-backend, kind: ClusterSecretStore}`, `target {name: chaski-secrets, creationPolicy: Owner}`, and an explicit `data:` list — one entry per consumer, each pointing at the **existing** key so nothing is duplicated or rotated:

  ```yaml
  data:
    - secretKey: FLUX_MAIN_WEBHOOK_TOKEN
      remoteRef:
        key: infra/kubernetes/main/flux-system/webhook
        property: TOKEN
    - secretKey: ATLANTIS_TERRAFORM_HARBOR_WEBHOOK_SECRET
      remoteRef:
        key: infra/kubernetes/main/atlantis-system/atlantis-techtales-io-terraform-harbor
        property: ATLANTIS_GH_WEBHOOK_SECRET
  ```

  Fill the remaining nine Atlantis entries from the instance list in `kubernetes/main/apps/atlantis-system/{techtales-io,tyriis}/flux-sync.yaml` — `atlantis-techtales-io-terraform-{discord,gcloud,github,gworkspace,harbor,minio,pocket-id,unifi,vault}` and `atlantis-tyriis-terraform-github`. `ATLANTIS_GH_WEBHOOK_SECRET` exists on all ten (the per-instance patch adds the org/app keys, not the webhook secret). Names: `ATLANTIS_<REPO-UPPER-UNDERSCORE>_WEBHOOK_SECRET`, matching the `env` references in Task 3 exactly.

- [ ] **Step 5: Render and lint**

Run: `task flate:test -- main`
Expected: PASS, `chaski` HelmRelease rendered.
Run: `task deadvalues:check-values`
Expected: PASS — every value key used above must be one of the chart keys (`replicaCount`, `podDisruptionBudget.*`, `resources`, `config.*`, `monitoring.serviceMonitor.enabled`, `deploymentAnnotations`, `initContainers`, `envFrom`) or deadvalues will fail the build.

- [ ] **Step 6: Commit**

```bash
git add kubernetes/main/apps/networking/chaski kubernetes/main/apps/networking/kustomization.yaml
git commit -m "feat(chaski): scaffold webhook relay on main"
```

---

### Task 3: Route table for the ten Atlantis instances

**Files:**
- Modify: `kubernetes/main/apps/networking/chaski/app/helm-release.yaml`

**Interfaces:**
- Consumes: env var names from Task 2 Step 4 (must match character for character).
- Produces: URLs `POST /hooks/<consumer>`, consumed by Task 4's HTTPRoute, Task 5/6's GitHub migration.

- [ ] **Step 1: Resolve each target Service name and port from the live cluster, not by guessing.** app-template v5 names the Service `<fullname>-<serviceKey>`:

Run: `kubectl -n atlantis-system get svc -l app.kubernetes.io/name=atlantis-techtales-io-terraform-harbor -o custom-columns=NAME:.metadata.name,PORT:.spec.ports[0].port`
Expected: one Service, port `4141`. Record all ten. If a name differs from `<release>-main`, use what the cluster reports.

- [ ] **Step 2: Add `config.targets`** — one per instance, retry capped at 1 because Atlantis is not idempotent:

  ```yaml
  targets:
    atlantis-techtales-io-terraform-harbor:
      http:
        method: POST
        url: http://atlantis-techtales-io-terraform-harbor-main.atlantis-system.svc.cluster.local:4141/events
        retry:
          attempts: 1
  ```

- [ ] **Step 3: Add `config.routes`** — one per instance. `message` stays unset (body verbatim); the gate is defence-in-depth so a webhook pointed at the wrong path cannot inject another repo's payload:

  ```yaml
  routes:
    atlantis-techtales-io-terraform-harbor:
      description: Atlantis webhook for techtales-io/terraform-harbor
      target: atlantis-techtales-io-terraform-harbor
      whenExpr: 'payload.repository.full_name == "techtales-io/terraform-harbor" && payload.sender.type != "Bot"'
      verify:
        github:
          secret: '{{ env "ATLANTIS_TERRAFORM_HARBOR_WEBHOOK_SECRET" }}'
      headers:
        Content-Type: application/json
        X-GitHub-Event: '{{ index .headers "x-github-event" }}'
        X-GitHub-Delivery: '{{ index .headers "x-github-delivery" }}'
        X-Hub-Signature: '{{ index .headers "x-hub-signature" }}'
        X-Hub-Signature-256: '{{ index .headers "x-hub-signature-256" }}'
  ```

  `whenExpr` must match each instance's `REPO` substitute (`terraform-harbor` → `techtales-io/terraform-harbor`; the `tyriis` instance → `tyriis/terraform-github`). Both `X-Hub-Signature` variants are forwarded: flux falls back to the SHA-1 header, and forwarding both costs nothing.

  Do **not** add a `route.whenExpr` guard on `action` — Atlantis decides what it accepts; a ping delivery must still produce a `200` for the GitHub UI to show a healthy hook.

- [ ] **Step 4: Verify the config renders and validates**

Run: `task flate:test -- main`
Expected: PASS.
After Flux applies it (Task 4 not yet done, so no traffic): `kubectl -n networking logs deploy/chaski -c chaski --tail=50` shows the route table loaded with no `render_error`/`gate_error` and the init container passed `validate`.

- [ ] **Step 5: Dry-run each route** (no relay, no target hit):

Run: `kubectl -n networking exec deploy/chaski -- wget -qO- --post-data='{}' 'http://localhost:8080/hooks/atlantis-techtales-io-terraform-harbor?dryRun=1'`
Expected: a plan naming the target — `401` is the *correct* answer here for an unsigned request, which proves `verify` is wired; `404` means the route name is wrong; `500`/`render_error` means a template bug.

- [ ] **Step 6: Commit**

```bash
git add kubernetes/main/apps/networking/chaski/app/helm-release.yaml
git commit -m "feat(chaski): route atlantis webhooks in-cluster"
```

---

### Task 4: Public hostname

**Files:**
- Create: `kubernetes/main/apps/networking/chaski/app/http-route.yaml`
- Modify: `kubernetes/main/apps/networking/chaski/app/kustomization.yaml`
- Modify: `kubernetes/main/apps/networking/cloudflared/app/resources/config.yaml`

**Interfaces:**
- Consumes: `Service/chaski:8080` from Task 2.
- Produces: `https://github-hooks.techtales.io/hooks/<route>`, consumed by Tasks 5–6's GitHub config and Task 7's Gatus probe.

- [ ] **Step 1: `http-route.yaml`** — same shape as `kubernetes/main/apps/flux-system/flux-instance/webhook/helm-release.yaml`'s route block: `parentRefs: [{name: envoy, namespace: networking, sectionName: https}]`, `hostnames: [github-hooks.techtales.io]`, `matches: [{path: {type: PathPrefix, value: /hooks/}}]`, `backendRefs: [{name: chaski, port: 8080}]`. Annotations: `external-dns/cloudflare: "true"`, `external-dns/unifi: "true"`, plus the Gatus endpoint with `group: external`, `dns-resolver: tcp://1.1.1.1:53`, `conditions: ["[STATUS] == 404"]` (a `GET` on a `/hooks/` path is correctly a 404; this mirrors the `flux-webhook` probe).

- [ ] **Step 2: Add the tunnel ingress entry** at the top of the `ingress:` list in `cloudflared/app/resources/config.yaml`, matching the existing self-referencing style used by `flux-webhook` and `flux-webhook-utility`:

  ```yaml
  - hostname: github-hooks.techtales.io
    service: https://github-hooks.techtales.io
  ```

- [ ] **Step 3: Render, lint, apply via Flux**

Run: `task flate:test -- main && task lint:yaml`
Expected: PASS.
Then reconcile and confirm: `kubectl -n networking get httproute chaski -o jsonpath='{.status.parents[0].conditions}'` → `Accepted=True`, `ResolvedRefs=True`.

- [ ] **Step 4: Prove the edge answers correctly**

Run: `curl -sS -o /dev/null -w '%{http_code}\n' https://github-hooks.techtales.io/hooks/nope`
Expected: `404`.
Run: `curl -sS -o /dev/null -w '%{http_code}\n' -X POST --data '{}' https://github-hooks.techtales.io/hooks/atlantis-techtales-io-terraform-harbor`
Expected: `401` (signature missing). Any `502`/`503` means the tunnel→gateway→Service chain is wrong, not chaski.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/networking/chaski/app kubernetes/main/apps/networking/cloudflared/app/resources/config.yaml
git commit -m "feat(chaski): expose github-hooks.techtales.io"
```

---

### Task 5: Canary one Atlantis instance

**Files:** none (GitHub-side change only).

**Interfaces:**
- Consumes: route URL from Task 4, secret already identical by construction.
- Produces: the proven migration procedure Tasks 6 repeats nine times.

- [ ] **Step 1: Pick the least valuable instance** — `atlantis-tyriis-terraform-github` (one repo, one operator). Record its current hook via the GitHub MCP server (`list_repository_webhooks` for `tyriis/terraform-github`): URL, events, content type `application/json`, secret.

- [ ] **Step 2: Repoint only the payload URL** to `https://github-hooks.techtales.io/hooks/atlantis-tyriis-terraform-github`. Secret, events and `active` stay untouched.

- [ ] **Step 3: Deliver a real event.** Redeliver an existing `pull_request` delivery from the GitHub webhook UI.

Expected: GitHub shows `200`; `kubectl -n networking logs deploy/chaski --tail=20` shows `relay ok` for that route with `X-Chaski-Result: relayed`; Atlantis posts a plan comment on the PR; `kubectl -n atlantis-system logs deploy/atlantis-tyriis-terraform-github --tail=50` shows the request validated (no `unable to verify signature`).

- [ ] **Step 4: Prove the negative paths**

Run: `curl -sS -X POST --data '{}' -H 'Content-Type: application/json' https://github-hooks.techtales.io/hooks/atlantis-tyriis-terraform-github`
Expected: `401`.
Redeliver the **wrong** event type (e.g. a `push` to a repo this instance does not serve, via the URL of a different route).
Expected: `204` from the `whenExpr` gate, and no Atlantis log line.

- [ ] **Step 5: Prove rollback** by restoring the original payload URL, redelivering, confirming a plan comment appears with chaski out of the path, then re-applying the chaski URL. Document the two-step rollback in the PR description.

- [ ] **Step 6: Commit the runbook** — append the exact steps above to `kubernetes/main/apps/networking/chaski/README.md` (create it), including the rollback pair of URLs per instance.

```bash
git add kubernetes/main/apps/networking/chaski/README.md
git commit -m "docs(chaski): add atlantis cutover runbook"
```

---

### Task 6: Migrate the other nine, then close the 11 public hosts

**Files:**
- Modify: `kubernetes/components/atlantis/helm-release.yaml` (remove `route.webhook`)
- Modify: `kubernetes/main/apps/networking/cloudflared/app/resources/config.yaml` (remove 11 entries)

**Interfaces:**
- Consumes: Task 5's procedure.
- Produces: `github-hooks.techtales.io` as the only public Atlantis webhook hostname.

- [ ] **Step 1: Repoint nine payload URLs** the same way, one instance at a time, redelivering a real event after each. Do not batch: a `whenExpr` typo shows up as a silent `204` for exactly one repo.

- [ ] **Step 2: Wait 24h** with all ten on chaski, then confirm from the GitHub side that every hook shows a recent successful delivery (MCP `list_repository_webhooks` / deliveries), and that `chaski_target_sends_total{outcome!="success"}` is zero over the window.

- [ ] **Step 3: Remove the `route.webhook` block** from `kubernetes/components/atlantis/helm-release.yaml` — this deletes ten `<release>-webhook.techtales.io` HTTPRoutes, their `external-dns` records and their Gatus probes in one edit.

- [ ] **Step 4: Remove the eleven atlantis webhook entries** from `cloudflared/app/resources/config.yaml`, **including the stale `atlantis-techtales-io-terraform-opnsense-webhook.techtales.io`** (no such instance exists). Do not touch `kromgo`'s duplicate entry — unrelated drift, separate issue.

- [ ] **Step 5: Verify nothing still resolves**

Run: `dig +short atlantis-techtales-io-terraform-harbor-webhook.techtales.io` (with the LAN resolver)
Expected: empty after external-dns' TXT-aware cleanup — `policy: sync` removes the record once the HTTPRoute is gone.
Run: `kubectl -n networking get httproute | grep -c webhook`
Expected: `0` for `<release>-webhook`, `1` for `flux-webhook`/`flux-webhook-utility` (untouched).

- [ ] **Step 6: Commit**

```bash
git add kubernetes/components/atlantis/helm-release.yaml kubernetes/main/apps/networking/cloudflared/app/resources/config.yaml
git commit -m "refactor(atlantis): drop per-instance webhook hosts"
```

---

### Task 7: Observability — the part that makes this safe

**Files:**
- Create: `kubernetes/main/apps/networking/chaski/app/{vm-service-scrape,vm-rule}.yaml`
- Modify: `kubernetes/main/apps/networking/chaski/app/kustomization.yaml`

**Interfaces:**
- Consumes: `metrics:8081` service port from Task 2.
- Produces: alerts that make a downstream failure visible within one delivery, replacing the per-instance Gatus probes removed in Task 6.

- [ ] **Step 1: `vm-service-scrape.yaml`** — copy `konflate`'s shape: `namespaceSelector.matchNames: [networking]`, `selector.matchLabels {app.kubernetes.io/name: chaski, app.kubernetes.io/instance: chaski}`, `endpoints: [{port: metrics, path: /metrics, interval: 30s, scrapeTimeout: 10s}]`.

- [ ] **Step 2: `vm-rule.yaml`** — alerts on the metrics that actually move. `chaski_webhook_rejected_total{reason}` is **wrong** (it counts inbound rejects only and never fires on downstream failure):

  ```yaml
  - alert: ChaskiRelayErrors
    expr: sum by (route) (rate(chaski_relays_total{result=~"relay_error|render_error|gate_error"}[5m])) > 0
    for: 5m
    labels: {severity: warning}
  - alert: ChaskiTargetSendFailing
    expr: sum by (target) (rate(chaski_target_sends_total{outcome!="success"}[5m])) > 0
    for: 10m
    labels: {severity: critical}
    annotations: {summary: "Webhook relay to {{ $labels.target }} is failing"}
  - alert: ChaskiDown
    expr: up{job=~".*chaski.*"} == 0
    for: 5m
    labels: {severity: critical}
  ```

  Confirm the exported metric names against `curl -s localhost:8081/metrics` in Step 4 and correct the rule if the label set differs (`route`/`target`/`result` must exist before this ships).

- [ ] **Step 3: Add the Gatus endpoint** if Task 4's annotation was not enough, and keep exactly one probe for the new host.

- [ ] **Step 4: Verify**

Run: `task flate:test -- main`
Then: `kubectl -n networking exec deploy/chaski -- wget -qO- http://localhost:8081/metrics | grep -E 'chaski_(relays|target_sends|webhook_rejected)_total'`
Expected: the series exist with `route`/`target` labels.
Then confirm the rule evaluates: query `ChaskiTargetSendFailing` in vmui (`https://metrics.techtales.io`) → no data / no firing.

- [ ] **Step 5: Force a failure to prove the alert fires** — stop one Atlantis deployment's pods briefly (`kubectl -n atlantis-system scale deploy/atlantis-tyriis-terraform-github --replicas=0`), redeliver a hook, confirm `204`/`500` + `ChaskiTargetSendFailing` pending, then scale back to 1 and confirm recovery. Record the observed behaviour in the README.

- [ ] **Step 6: Commit**

```bash
git add kubernetes/main/apps/networking/chaski
git commit -m "feat(chaski): scrape metrics and alert on relay failures"
```

---

### Task 8 (gated): flux through chaski — only if the SPIKE clears

**Files:**
- Modify: `kubernetes/main/apps/networking/chaski/app/helm-release.yaml`
- Modify: `kubernetes/main/apps/networking/chaski/app/external-secret.yaml` (already carries `FLUX_MAIN_WEBHOOK_TOKEN` from Task 2)

**Interfaces:**
- Consumes: `Receiver/flux-system` — its `status.webhookPath` is the target path.
- Produces: nothing anything else depends on.

**Gate:** do not start until the ADR records an explicit "yes". Default is flux stays direct.

- [ ] **Step 1: Read the receiver's path**

Run: `kubectl -n flux-system get receiver flux-system -o jsonpath='{.status.webhookPath}'`
Expected: `/hook/<sha256>`.

- [ ] **Step 2: Add the route+target**, `message` unset, headers `X-GitHub-Event` + `X-Hub-Signature-256` forwarded, `retry.attempts: 2` (reconciliation is idempotent), `whenExpr: 'payload.repository.full_name == "tyriis/home-ops"'`, and a comment on the target URL recording the coupling: the path changes if the token rotates, because flux derives it from `sha256(token+name+namespace)`.

  Note: with `type: github`, the published path is not itself a credential — that stays true behind chaski.

- [ ] **Step 3: Repoint the `tyriis/home-ops` receiver hook, redeliver a push, confirm `kubectl -n flux-system get receiver flux-system -o jsonpath='{.status.lastHandledReconcileAt}'` advances and a `GitRepository` reconcile is triggered (`flux get sources git -A`).**

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/networking/chaski/app
git commit -m "feat(chaski): relay flux receiver webhooks"
```

---

### Task 9 (gated): doco-cd webhooks — only if polling is declared insufficient

**Files:**
- Modify: `kubernetes/main/apps/networking/chaski/app/helm-release.yaml`
- Modify: `kubernetes/main/apps/networking/chaski/app/external-secret.yaml`
- Modify: the eight docker-host `.env` files that carry the commented `WEBHOOK_SECRET_FILE`

**Gate:** enabling webhooks reverses the undocumented polling practice (interval 180). It needs its own decision and its own secret.

- [ ] **Step 1: Inventory the eight hosts** from the compose/env files in the repo (`docker/**`), recording each host's reachable address from main's network and its configured repositories.

- [ ] **Step 2: Add one route `doco-cd` with one target per host** (`whenExpr` per target only where a host serves a subset), and one shared `DOCO_CD_WEBHOOK_SECRET` in OpenBao; each host's `WEBHOOK_SECRET_FILE` reads the same value, so passthrough again needs no re-signing.

- [ ] **Step 3: Enable the secret on one host**, push to a repo it watches, confirm a deploy within seconds instead of up to 180s. Then the rest.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/networking/chaski docker
git commit -m "feat(doco-cd): receive deploys via webhook relay"
```

---

### Explicitly out of scope

- **n8n.** `chaski` cannot do a suffix passthrough, and n8n's `/webhook/<path>` segments live only on the `n8n-data` PVC — they are not repo-derivable, and putting them in a public ConfigMap would turn each path into published text (n8n treats the path as the credential). Keep `n8n-webhook.techtales.io` direct; the only defensible hardening is enumerating workflow paths and adding per-path routes, which is a separate issue.
- **Utility cluster.** Its flux receiver stays direct. A chaski on main would reach it only over the public hostname (extra WAN hop, TLS, CC proxy) for a single endpoint that already works.
- **Auth for kromgo / ceph-dashboard style consumers** that cannot present a bearer token (ADR 0020's known follow-up) — unrelated to webhook relay.
