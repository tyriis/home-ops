# SearXNG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a LAN-only SearXNG instance in the `ai` namespace as the Open WebUI RAG search backend and a browser search UI at `https://search.techtales.io`.

**Architecture:** A new Flux Kustomization path `kubernetes/main/apps/ai/searxng/` holding an OCIRepository for `app-template` 5.2.1, a ConfigMap carrying `settings.yml`, an ExternalSecret sourcing `SEARXNG_SECRET` from OpenBao, an ingress-only NetworkPolicy, and the HelmRelease. Three existing files are touched: the `ai` namespace Kustomization registration, `hermes-agent`'s egress allow-list, and `open-webui`'s RAG environment variables.

**Tech Stack:** Flux CD, bjw-s `app-template` 5.2.1 (OCI), External Secrets Operator with the `openbao-backend` ClusterSecretStore, Gateway API via Envoy Gateway, Cilium NetworkPolicy, Talos/Kubernetes.

**Design reference:** `docs/superpowers/specs/2026-09-19-searxng-design.md`

---

## Prerequisites

### P1. Branch

The branch already exists. Confirm before starting:

```bash
git branch --show-current
```

Expected: `feature/setup-searxng`

### P2. OpenBao secret (manual, blocks runtime health)

The ExternalSecret reads `infra/kubernetes/main/ai/searxng`. This path must exist **before** the
Kustomization is reconciled, or the ExternalSecret will report `SecretSyncedError`.

```bash
bao kv put infra/kubernetes/main/ai/searxng SEARXNG_SECRET="$(openssl rand -base64 48)"
```

Verify:

```bash
bao kv get -format=json infra/kubernetes/main/ai/searxng | jq '.data.data | keys'
```

Expected: `["SEARXNG_SECRET"]`

There is no `put` task in `.taskfiles/openbao/Taskfile.yaml` — it only provides `copy`, `move`, and
`delete` — so this command is run directly against the OpenBao CLI.

**Important:** This key must **not** be created by Terraform or committed to git. It is a runtime
signing key for session/preference cookies.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `kubernetes/main/apps/ai/searxng/flux-sync.yaml` | Flux Kustomization; entry point registering the app |
| `kubernetes/main/apps/ai/searxng/app/kustomization.yaml` | Lists the resources below |
| `kubernetes/main/apps/ai/searxng/app/oci-repository.yaml` | `app-template` 5.2.1 OCI source |
| `kubernetes/main/apps/ai/searxng/app/helm-release.yaml` | The HelmRelease and all values |
| `kubernetes/main/apps/ai/searxng/app/configmap.yaml` | `settings.yml` |
| `kubernetes/main/apps/ai/searxng/app/external-secret.yaml` | `SEARXNG_SECRET` from OpenBao |
| `kubernetes/main/apps/ai/searxng/app/network-policy.yaml` | Ingress-only policy |
| `kubernetes/main/apps/ai/kustomization.yaml` | **Modify** — register the app |
| `kubernetes/main/apps/hermes-agent/app/network-policy.yaml` | **Modify** — egress allow to SearXNG |
| `kubernetes/main/apps/ai/open-webui/app/helm-release.yaml` | **Modify** — RAG wiring |

---

## Task 1: SearXNG chart source and app skeleton

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/app/oci-repository.yaml`
- Create: `kubernetes/main/apps/ai/searxng/app/kustomization.yaml`

- [ ] **Step 1: Create the OCI chart source**

Create `kubernetes/main/apps/ai/searxng/app/oci-repository.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: searxng
spec:
  interval: 30m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 5.2.1
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
```

The URL is `.../helm/app-template`, **not** `.../charts/app-template`. The `charts/` path returns
`NAME_UNKNOWN` and is a bad reference that circulates in kubesearch output. This exact URL was
verified with `helm show chart oci://ghcr.io/bjw-s-labs/helm/app-template --version 5.2.1`.

- [ ] **Step 2: List the app resources**

Create `kubernetes/main/apps/ai/searxng/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./configmap.yaml
  - ./external-secret.yaml
  - ./helm-release.yaml
  - ./network-policy.yaml
  - ./oci-repository.yaml
```

- [ ] **Step 3: Validate the chart reference resolves**

Run:

```bash
helm show chart oci://ghcr.io/bjw-s-labs/helm/app-template --version 5.2.1
```

Expected: output containing `name: app-template` and `version: 5.2.1`.

---

## Task 2: `settings.yml` ConfigMap

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/app/configmap.yaml`

- [ ] **Step 1: Create the ConfigMap**

Create `kubernetes/main/apps/ai/searxng/app/configmap.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/core/configmap_v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: searxng-config
data:
  settings.yml: |
    use_default_settings: true

    general:
      instance_name: SearXNG

    search:
      safe_search: 0
      autocomplete: duckduckgo
      default_lang: en-US
      formats:
        - html
        - json

    server:
      base_url: https://search.techtales.io/
      limiter: false
      public_instance: false
      image_proxy: true
      method: GET

    ui:
      default_locale: en
      default_theme: simple
      theme_args:
        simple_style: auto
```

Notes for the implementer:

- There is deliberately **no `secret_key`**. The `SEARXNG_SECRET` environment variable from the
  ExternalSecret overrides `server.secret_key` at runtime, keeping the ConfigMap free of secrets.
- `formats` **must** include `json`. Without it, `format=json` returns HTTP 403 and Open WebUI's RAG
  search fails.
- `limiter: false` is intentional. See the design document — the hard-coded `API_MAX = 4` per hour
  would break the Open WebUI client, and the exemption required is too broad to justify.

- [ ] **Step 2: Validate YAML syntax**

Run:

```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/ai/searxng/app/configmap.yaml
```

Expected: no output (clean).

---

## Task 3: `SEARXNG_SECRET` ExternalSecret

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/app/external-secret.yaml`

- [ ] **Step 1: Create the ExternalSecret**

Create `kubernetes/main/apps/ai/searxng/app/external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name searxng
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: openbao-backend
    kind: ClusterSecretStore
  target:
    name: *name
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        SEARXNG_SECRET: "{{ .SEARXNG_SECRET }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/ai/searxng
```

The resulting Secret is named `searxng`, which is what the HelmRelease consumes via `envFrom`.

- [ ] **Step 2: Validate YAML syntax**

Run:

```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/ai/searxng/app/external-secret.yaml
```

Expected: no output (clean).

---

## Task 4: Ingress-only NetworkPolicy

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/app/network-policy.yaml`

- [ ] **Step 1: Create the NetworkPolicy**

Create `kubernetes/main/apps/ai/searxng/app/network-policy.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/networking.k8s.io/networkpolicy_v1.json
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${APP}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: ${APP}
  policyTypes:
    - Ingress
  ingress:
    # Same namespace: Open WebUI
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8080
    # hermes-agent namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: hermes-agent
      ports:
        - protocol: TCP
          port: 8080
    # Envoy Gateway data plane for the browser UI
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: networking
      ports:
        - protocol: TCP
          port: 8080
```

**Why `app.kubernetes.io/name: ${APP}` is correct:** `helm template` of `app-template` 5.2.1 with
release name `searxng` renders pod labels `app.kubernetes.io/name: searxng`,
`app.kubernetes.io/instance: searxng`, `app.kubernetes.io/controller: searxng`. The release name is
used, not `app-template`. Verified locally — do not change this selector based on the library
chart's internal helper names.

**Why no egress rules:** SearXNG must reach arbitrary public internet hosts for every search engine.
An egress policy would have to allow `0.0.0.0/0` on 443/80, which provides no protection. `policyTypes`
deliberately omits `Egress`.

- [ ] **Step 2: Validate YAML syntax**

Run:

```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/ai/searxng/app/network-policy.yaml
```

Expected: no output (clean).

---

## Task 5: HelmRelease

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/app/helm-release.yaml`

- [ ] **Step 1: Create the HelmRelease**

Create `kubernetes/main/apps/ai/searxng/app/helm-release.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app searxng
spec:
  driftDetection:
    mode: enabled
  interval: 30m
  chartRef:
    kind: OCIRepository
    name: *app
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
    controllers:
      searxng:
        replicas: 1
        annotations:
          reloader.stakater.com/auto: "true"
        pod:
          securityContext:
            runAsNonRoot: true
            runAsUser: 977
            runAsGroup: 977
            fsGroup: 977
            fsGroupChangePolicy: OnRootMismatch
            seccompProfile:
              type: RuntimeDefault
        containers:
          app:
            image:
              repository: ghcr.io/searxng/searxng
              tag: 2026.9.19-e831fc2a1@sha256:547fdc19b45510ea1c0bc65ffadab3fcdde1ab1efd7fe696602284ba54d795ca
            env:
              TZ: Europe/Vienna
              SEARXNG_BASE_URL: https://search.techtales.io
              SEARXNG_PORT: &port 8080
              GRANIAN_HOST: 0.0.0.0
            envFrom:
              - secretRef:
                  name: *app
            probes:
              readiness: &probes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /healthz
                    port: *port
                  initialDelaySeconds: 5
                  periodSeconds: 10
                  timeoutSeconds: 2
                  failureThreshold: 3
              liveness: *probes
            resources:
              requests:
                cpu: 50m
                memory: 256Mi
              limits:
                memory: 1Gi
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
    service:
      app:
        ports:
          http:
            port: *port
    route:
      app:
        annotations:
          external-dns/unifi: "true"
          gethomepage.dev/enabled: "true"
          gethomepage.dev/name: SearXNG
          gethomepage.dev/group: AI
          gethomepage.dev/icon: searxng
          gethomepage.dev/description: Privacy-respecting metasearch
        hostnames:
          - search.techtales.io
        parentRefs:
          - name: envoy
            namespace: networking
            sectionName: https
    persistence:
      config:
        type: configMap
        name: searxng-config
        globalMounts:
          - path: /etc/searxng/settings.yml
            subPath: settings.yml
            readOnly: true
      cache:
        type: emptyDir
        globalMounts:
          - path: /var/cache/searxng
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
```

Implementer notes:

- `runAsUser`/`runAsGroup`/`fsGroup` are `977` because that is the image's `searxng` user. Running
  non-root means the entrypoint skips its `chown` and `update-ca-certificates` steps, which is
  intended and safe because `settings.yml` is mounted read-only and already present.
- **No `capabilities.add`.** The community `CHOWN`/`SETGID`/`SETUID`/`DAC_OVERRIDE` additions are
  legacy from the pre-Granian uWSGI image and are unnecessary.
- `GRANIAN_HOST: 0.0.0.0` is required: the image hardcodes `::` and this cluster is IPv4-only.
- `/tmp` and `/var/cache/searxng` must be writable because the root filesystem is read-only and the
  SQLite caches live there.
- `/healthz` is the correct probe path. `/stats` is an HTML page and must not be used for probes.

- [ ] **Step 2: Render the chart with these values and inspect the pod spec**

Run:

```bash
helm template searxng oci://ghcr.io/bjw-s-labs/helm/app-template --version 5.2.1 \
  --set controllers.searxng.containers.app.image.repository=ghcr.io/searxng/searxng \
  --set controllers.searxng.containers.app.image.tag=test \
  --set service.app.ports.http.port=8080 \
  | grep -E "app.kubernetes.io/(name|instance):"
```

Expected: lines showing `app.kubernetes.io/name: searxng` and `app.kubernetes.io/instance: searxng`.
This confirms the NetworkPolicy selector from Task 4 will match.

---

## Task 6: Flux Kustomization and registration

**Files:**

- Create: `kubernetes/main/apps/ai/searxng/flux-sync.yaml`
- Modify: `kubernetes/main/apps/ai/kustomization.yaml`

- [ ] **Step 1: Create the Flux Kustomization**

Create `kubernetes/main/apps/ai/searxng/flux-sync.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app searxng
  namespace: &namespace ai
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/ai/searxng/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: external-secrets-stores
      namespace: secops
  postBuild:
    substitute:
      APP: *app
      NAMESPACE: *namespace
```

`dependsOn` guarantees the `openbao-backend` ClusterSecretStore exists before the ExternalSecret is
reconciled. There is no `volsync` or `rook-ceph-cluster` dependency because SearXNG has no
persistent volume.

- [ ] **Step 2: Register the app in the `ai` namespace**

Modify `kubernetes/main/apps/ai/kustomization.yaml` so the `resources` list becomes:

```yaml
resources:
  - ./namespace.yaml
  - ./llm-guard/flux-sync.yaml
  - ./olla/flux-sync.yaml
  - ./ollama/flux-sync.yaml
  - ./open-webui/flux-sync.yaml
  - ./searxng/flux-sync.yaml
```

- [ ] **Step 3: Render the Kustomization**

Run:

```bash
kustomize build kubernetes/main/apps/ai
```

Expected: all five `flux-sync.yaml` Kustomizations and `namespace.yaml` render, including the new
`searxng` Kustomization. No errors.

- [ ] **Step 4: Commit the new app**

```bash
git add kubernetes/main/apps/ai/searxng kubernetes/main/apps/ai/kustomization.yaml
git commit -m "feat(searxng): add lan-only search deployment"
```

---

## Task 7: Allow `hermes-agent` egress to SearXNG

**Files:**

- Modify: `kubernetes/main/apps/hermes-agent/app/network-policy.yaml`

- [ ] **Step 1: Add the egress rule**

`hermes-agent` has a default-deny egress policy, so the ingress allowance in Task 4 is inert without
a matching rule here. Append to the `egress` list in
`kubernetes/main/apps/hermes-agent/app/network-policy.yaml`, immediately after the existing
`olla` rule and before the `192.168.100.10/32` rule:

```yaml
    # Allow egress to searxng in the ai namespace
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ai
          podSelector:
            matchLabels:
              app.kubernetes.io/name: searxng
      ports:
        - protocol: TCP
          port: 8080
```

Do **not** modify `hermes-agent`'s ConfigMap. Its `web.search_backend` stays on `firecrawl`; only
network reachability to SearXNG is opened, so the path exists if it is switched later.

- [ ] **Step 2: Validate YAML syntax**

Run:

```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/hermes-agent/app/network-policy.yaml
```

Expected: no output (clean).

- [ ] **Step 3: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/app/network-policy.yaml
git commit -m "feat(hermes-agent): allow egress to searxng"
```

---

## Task 8: Wire Open WebUI RAG web search

**Files:**

- Modify: `kubernetes/main/apps/ai/open-webui/app/helm-release.yaml` (around lines 51-54)

- [ ] **Step 1: Replace the stale commented block**

The existing block uses variable names Open WebUI v0.11.3 does not read:

```yaml
              # ENABLE_RAG_WEB_SEARCH: true
              # ENABLE_SEARCH_QUERY: true
              # RAG_WEB_SEARCH_ENGINE: searxng
              # SEARXNG_QUERY_URL: http://searxng:8080/search?q=<query>
```

Replace it with:

```yaml
              ENABLE_WEB_SEARCH: "true"
              WEB_SEARCH_ENGINE: searxng
              SEARXNG_QUERY_URL: http://searxng.ai.svc.cluster.local:8080/search
              SEARXNG_LANGUAGE: en-US
              WEB_SEARCH_RESULT_COUNT: "5"
```

Implementer notes:

- `ENABLE_WEB_SEARCH` and `WEB_SEARCH_ENGINE` are the v0.11.3 names; the `RAG_WEB_SEARCH_*` family has
  no backward-compatible alias in that version.
- `SEARXNG_QUERY_URL` must be the **bare `/search` endpoint**. The legacy
  `<query>` placeholder form causes Open WebUI to strip everything after `?`. Open WebUI appends and
  URL-encodes all parameters itself, including `format=json`.
- Use the fully qualified `searxng.ai.svc.cluster.local` rather than the short `searxng` name.
- `SEARXNG_LANGUAGE: en-US` matches the browser UI default. Language is overridable per request by
  Open WebUI; safe search is not — the client hard-codes `safesearch=1`.

- [ ] **Step 2: Verify no stale variable names remain**

Run:

```bash
grep -rn "RAG_WEB_SEARCH\|ENABLE_RAG_WEB_SEARCH" kubernetes/main/apps/ai/open-webui/
```

Expected: no matches.

- [ ] **Step 3: Validate YAML syntax**

Run:

```bash
yamllint -c .yamllint.yaml kubernetes/main/apps/ai/open-webui/app/helm-release.yaml
```

Expected: no output (clean).

- [ ] **Step 4: Commit**

```bash
git add kubernetes/main/apps/ai/open-webui/app/helm-release.yaml
git commit -m "feat(open-webui): enable searxng web search"
```

---

## Task 9: Repository-wide static verification

- [ ] **Step 1: Run the repository linters**

Run:

```bash
task lint
```

Expected: `markdownlint`, `yamllint`, and `prettier` all pass with no findings.

- [ ] **Step 2: Run pre-commit across the repository**

Run:

```bash
task pre-commit
```

Expected: all hooks pass. Note that `.pre-commit-config.yaml` excludes `^docs/superpowers/.*`, so
the design and plan documents are intentionally not linted by this hook.

- [ ] **Step 3: Render the Flux entrypoint**

Run:

```bash
task flate:test -- main
```

Expected: `flate test all --path kubernetes/main/flux` completes without errors, proving the new
Kustomization composes into the cluster entrypoint.

- [ ] **Step 4: Confirm no unrelated files were staged**

Run:

```bash
git status --porcelain
```

Expected: only the SearXNG app directory, the `ai` Kustomization, the `hermes-agent` NetworkPolicy,
and the `open-webui` HelmRelease appear as changes belonging to this work. Pre-existing unrelated
modifications (`.gitignore`, `AGENTS.md`, `docker/**`, `docs/superpowers/**`, `graphify-out/**`)
remain unstaged and untouched.

---

## Task 10: Cluster verification (manual, requires cluster access)

These steps must be run by a human with cluster credentials. The implementing agent has no cluster
access in this environment.

- [ ] **Step 1: Confirm the OpenBao key exists** (Prerequisite P2)

```bash
bao kv get -format=json infra/kubernetes/main/ai/searxng | jq '.data.data | keys'
```

Expected: `["SEARXNG_SECRET"]`

- [ ] **Step 2: Reconcile the source and the Kustomization**

```bash
flux reconcile source git flux-system
flux reconcile kustomization searxng -n ai --with-source
```

Expected: `Applied revision` and a successful Kustomization status.

- [ ] **Step 3: Check the ExternalSecret synced**

```bash
kubectl get externalsecret searxng -n ai
```

Expected: `STATUS` = `SecretSynced`, `READY` = `True`.

- [ ] **Step 4: Check the HelmRelease and pod**

```bash
kubectl get helmrelease searxng -n ai
kubectl get pods -n ai -l app.kubernetes.io/name=searxng
```

Expected: HelmRelease `READY` = `True`; one pod `Running` and `Ready`.

- [ ] **Step 5: Confirm the pod runs unprivileged**

```bash
kubectl get pod -n ai -l app.kubernetes.io/name=searxng \
  -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
```

Expected: `runAsUser: 977`, `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, caps dropped `ALL`
and no `add` entries.

- [ ] **Step 6: Verify the JSON API and the engine set**

```bash
kubectl run searxng-check --rm -it --restart=Never -n ai \
  --image=curlimages/curl -- \
  curl -s 'http://searxng.ai.svc.cluster.local:8080/search?q=kubernetes&format=json'
```

Expected: JSON containing a non-empty `results` array with `url`, `title`, and `content` fields. An
empty `results` array means engines are failing (see the design document's risk table).

- [ ] **Step 7: Verify the browser UI and DNS**

```bash
curl -sI https://search.techtales.io | head -1
```

Expected: `HTTP/2 200` (assuming LAN DNS resolution is in place via the UniFi provider).

- [ ] **Step 8: Verify Open WebUI RAG end to end**

In the Open WebUI UI, enable web search for a prompt and confirm results are returned rather than a
`WEB_SEARCH_ERROR`. Alternatively check the pod logs during a web-search request:

```bash
kubectl logs -n ai deploy/open-webui --tail=50 | grep -i "searxng\|web_search"
```

Expected: no `403`, `429`, or connection errors.

---

## Rollback

Revert the three commits and reconcile. The app introduces no persistent volumes, no database
migrations, and no shared-resource mutations, so rollback is fully reversible:

```bash
git revert --no-edit <commit-sha>
flux reconcile kustomization ai --with-source
```

The OpenBao key created in Prerequisite P2 is intentionally left in place; delete it manually if
the app is abandoned.

---

## Implementer Authorization

The implementer subagent is **authorized and expected** to make the following adjustments as needed
to satisfy the repository's CI, linters, and schema validators, without seeking further approval:

- Reformatting YAML to satisfy `yamllint`, `prettier`, and MegaLinter rules (indentation, line
  length, quoting, document terminators).
- Adding or adjusting `# yaml-language-server: $schema=` comments to match repository convention.
- Adding lint suppression comments where a third-party schema requires a value the linter rejects,
  with a brief comment explaining why.
- Adjusting `markdownlint` formatting in the design or plan documents.
- Re-pinning the container image digest if the tag referenced in Task 5 has been superseded,
  provided the new digest is verified against the same upstream tag with `docker manifest inspect`.

The implementer is **not** authorized to change: the namespace, the hostname, the chosen chart
version, the security context decisions, the limiter decision, or the NetworkPolicy allow-list.
Those are settled in the design document.
