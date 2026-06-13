# Hermes WebUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Hermes WebUI as a sidecar container to each existing hermes-agent pod, providing a web-based chat UI with passkey auth for each agent instance.

**Architecture:** A third container (webui) is added to the existing `hermes` controller in `helm-release.yaml`, running `ghcr.io/nesquena/hermes-webui` in gateway mode (`HERMES_WEBUI_CHAT_BACKEND=gateway`) pointing at `localhost:8642`. It reuses the agent's existing PVC and emptyDir volumes. Each instance gets its own HTTPRoute through Envoy Gateway.

**Tech Stack:** bjw-s/app-template (v5.0.1), Flux Kustomization, Envoy Gateway HTTPRoute, External Secrets (OpenBao), NetworkPolicy.

---

### Task 1: Add `HERMES_WEBUI_PASSWORD` to ExternalSecret

**Files:**
- Modify: `kubernetes/main/apps/hermes-agent/app/external-secret.yaml:18`

- [ ] **Step 1: Add the env mapping**

Add `HERMES_WEBUI_PASSWORD` to the ExternalSecret's template data, so it's available from OpenBao:

```yaml
        HERMES_WEBUI_PASSWORD: "{{ .HERMES_WEBUI_PASSWORD }}"
```

Insert it after `OPENCODE_ZEN_API_KEY` on line 25.

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/app/external-secret.yaml
git commit -m "feat(hermes-webui): add HERMES_WEBUI_PASSWORD to external-secret #9188"
```

---

### Task 2: Add `HOST` postBuild substitution to flux-sync

**Files:**
- Modify: `kubernetes/main/apps/hermes-agent/flux-sync.yaml:32,65,98,131`

- [ ] **Step 1: Add `HOST` to each instance's postBuild.substitute**

Each of the 4 Kustomization entries in `flux-sync.yaml` needs `HOST` added to `postBuild.substitute`. Match the instance name:

| Instance | Current `APP` value | `HOST` |
|----------|--------------------|--------|
| tyriis | `hermes-agent-tyriis` | `euphoria` |
| jazzlyn | `hermes-agent-jazzlyn` | `moira` |
| crowlex | `hermes-agent-crowlex` | `titan-ai` |
| techinik | `hermes-agent-techinik` | `nova` |

For example, the tyriis entry (lines 30-32):
```yaml
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data
      HOST: euphoria
```

Apply similarly for jazzlyn (`moira`), crowlex (`titan-ai`), techinik (`nova`).

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/flux-sync.yaml
git commit -m "feat(hermes-webui): add HOST postBuild substitution per instance #9188"
```

---

### Task 3: Add webui container, service port, route and persistence to helm-release

**Files:**
- Modify: `kubernetes/main/apps/hermes-agent/app/helm-release.yaml`

- [ ] **Step 1: Add the webui container after the dashboard container (line 128)**

Insert the webui container block after the dashboard container's `resources` line (line 128):

```yaml
          webui:
            image:
              repository: ghcr.io/nesquena/hermes-webui
              tag: 0.51.397@sha256:22af4e3a83f9e98abf46ac325a145fb3bd7d24953bccab30b3ec7928c6c6be4e
            command: ["python3", "/apptoo/server.py"]
            ports:
              - name: webui
                containerPort: 8787
                protocol: TCP
            env:
              HERMES_WEBUI_HOST: "0.0.0.0"
              HERMES_WEBUI_PORT: "8787"
              HERMES_WEBUI_CHAT_BACKEND: "gateway"
              HERMES_WEBUI_GATEWAY_BASE_URL: "http://localhost:8642"
              HOME: /opt/data
              HERMES_WEBUI_STATE_DIR: /opt/data/webui
            envFrom:
              - secretRef:
                  name: ${APP}-secret
            probes:
              liveness: &webuiProbes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: 8787
                  initialDelaySeconds: 10
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 5
              readiness: *webuiProbes
              startup:
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /health
                    port: 8787
                  initialDelaySeconds: 10
                  periodSeconds: 5
                  failureThreshold: 30
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
            resources:
              requests:
                cpu: 10m
                memory: 64Mi
              limits:
                memory: 256Mi
```

- [ ] **Step 2: Add webui port to the service (after line 138)**

```yaml
          webui:
            port: 8787
```

- [ ] **Step 3: Add route section (after the service block, line 139)**

```yaml
    route:
      webui:
        annotations:
          external-dns/cloudflare: "true"
          external-dns/unifi: "true"
          gethomepage.dev/enabled: "true"
          gethomepage.dev/description: Hermes WebUI Chat
          gethomepage.dev/group: AI
          gethomepage.dev/icon: mdi-chat
          gethomepage.dev/name: Hermes WebUI
          gatus.home-operations.com/endpoint: |
            group: external
        hostnames:
          - "${HOST}.techtales.io"
        parentRefs:
          - name: envoy
            namespace: networking
            sectionName: https
```

- [ ] **Step 4: Add webui persistence mounts (in the persistence section)**

Add webui mounts to existing volumes (data, tmp, run) in the `advancedMounts.hermes` section:

For `data` (existingClaim), add `webui` after `dashboard`:
```yaml
            webui:
              - path: *home
```

For `run` (emptyDir), add `webui` after `dashboard`:
```yaml
            webui:
              - path: /run
```

For `tmp` (emptyDir), add `webui` after `dashboard`:
```yaml
            webui:
              - path: /tmp
```

- [ ] **Step 5: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/app/helm-release.yaml
git commit -m "feat(hermes-webui): add webui sidecar container, service port, route and persistence #9188"
```

---

### Task 4: Update NetworkPolicy for webui port 8787

**Files:**
- Modify: `kubernetes/main/apps/hermes-agent/app/network-policy.yaml:23-25`

- [ ] **Step 1: Add ingress rule for port 8787 from networking namespace**

Add a second ingress rule after line 25 (after the existing port 8642 rule):

```yaml
    # Allow incoming traffic from Envoy Gateway for Hermes WebUI
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: networking
      ports:
        - protocol: TCP
          port: 8787
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/main/apps/hermes-agent/app/network-policy.yaml
git commit -m "feat(hermes-webui): add network policy ingress for webui port 8787 #9188"
```

---

## Verification

After all tasks are committed and deployed:

```bash
# Check Flux is happy
flux get kustomization -n hermes-agent

# Check pods are running with the new webui container
kubectl get pods -n hermes-agent

# Check the webui container is running inside each pod
kubectl get pods -n hermes-agent -o jsonpath='{.items[*].spec.containers[*].name}'

# Check HTTPRoutes are created
kubectl get httproute -n hermes-agent

# Test webui health endpoint
kubectl port-forward -n hermes-agent pod/hermes-agent-tyriis-xxx 8787:8787
curl http://localhost:8787/health

# Verify passkey auth works by hitting the webui URL
curl -I https://euphoria.techtales.io
```
