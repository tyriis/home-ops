# Talos OIDC Read-Only Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy `talosctl-oidc` server in each Talos cluster so users can authenticate via Pocket-ID and get short-lived `os:reader` Talos client certificates.

**Architecture:** One bjw-s app-template HelmRelease per cluster (main + utility), each holding its own Talos API CA. ExternalSecret pulls CA from OpenBao. Service type LoadBalancer with Cilium L2. Users point `talosctl-oidc login` at the appropriate server.

**Tech Stack:** talosctl-oidc-server, bjw-s app-template, Flux, External Secrets / OpenBao, Pocket-ID (existing), Cilium LoadBalancer

---

## File Structure

### Created

| File                                                                    | Purpose                                            |
| ----------------------------------------------------------------------- | -------------------------------------------------- |
| `kubernetes/main/apps/secops/talosctl-oidc/app/external-secret.yaml`    | Pull Talos API CA from OpenBao for main cluster    |
| `kubernetes/main/apps/secops/talosctl-oidc/app/helm-release.yaml`       | bjw-s app-template for main cluster                |
| `kubernetes/main/apps/secops/talosctl-oidc/app/kustomization.yaml`      | Kustomize resources for main                       |
| `kubernetes/main/apps/secops/talosctl-oidc/flux-sync.yaml`              | Flux Kustomization for main                        |
| `kubernetes/utility/apps/secops/talosctl-oidc/app/external-secret.yaml` | Pull Talos API CA from OpenBao for utility cluster |
| `kubernetes/utility/apps/secops/talosctl-oidc/app/helm-release.yaml`    | bjw-s app-template for utility cluster             |
| `kubernetes/utility/apps/secops/talosctl-oidc/app/kustomization.yaml`   | Kustomize resources for utility                    |
| `kubernetes/utility/apps/secops/talosctl-oidc/flux-sync.yaml`           | Flux Kustomization for utility                     |

### Modified

| File                                                | Change                                            |
| --------------------------------------------------- | ------------------------------------------------- |
| `kubernetes/main/apps/secops/kustomization.yaml`    | Add `./talosctl-oidc/flux-sync.yaml` to resources |
| `kubernetes/utility/apps/secops/kustomization.yaml` | Add `./talosctl-oidc/flux-sync.yaml` to resources |

---

### Task 1: Manual prerequisites

These steps can't be automated. Run them once before deploying.

- [ ] **Step 1: Create OIDC client in Pocket-ID**

In the Pocket-ID admin UI at `https://id.techtales.io/settings/admin/oidc-clients`, create a new client:

| Setting      | Value                                          |
| ------------ | ---------------------------------------------- |
| Name         | `talosctl`                                     |
| Client type  | Public                                         |
| Grant type   | Authorization Code                             |
| Redirect URI | `http://127.0.0.1:8900/callback`               |
| Scopes       | `openid`, `profile`, `email`, `offline_access` |
| PKCE         | Enabled (S256)                                 |

Note the **Client ID** — you'll use it in the helm-release files below.

- [ ] **Step 2: Extract Talos API CA from main cluster**

Run on a machine with talosctl access to the main cluster:

```bash
# Get the CA (this is the machine API CA, not the os-level CA)
talosctl get osrootsecrets -o yaml --context main
```

From the output, decode `spec.issuingCA.crt` and `spec.issuingCA.key`:

```bash
echo "<base64-crt>" | base64 -d > main-ca.crt
echo "<base64-key>" | base64 -d > main-ca.key
```

- [ ] **Step 3: Extract Talos API CA from utility cluster**

Same as step 2, but targeting the utility cluster:

```bash
talosctl get osrootsecrets -o yaml --context utility
```

Decode the cert and key:

```bash
echo "<base64-crt>" | base64 -d > util-ca.crt
echo "<base64-key>" | base64 -d > util-ca.key
```

- [ ] **Step 4: Store both CAs in OpenBao**

Write the CA PEM contents to OpenBao under the following paths:

```
vault kv put infra/kubernetes/main/secops/talosctl-oidc \
  ca_crt="$(cat main-ca.crt)" \
  ca_key="$(cat main-ca.key)"

vault kv put infra/kubernetes/utility/secops/talosctl-oidc \
  ca_crt="$(cat util-ca.crt)" \
  ca_key="$(cat util-ca.key)"
```

Verify:

```bash
vault kv get infra/kubernetes/main/secops/talosctl-oidc
vault kv get infra/kubernetes/utility/secops/talosctl-oidc
```

---

### Task 2: Utility cluster — create deployment files

**Files:**

- Create: `kubernetes/utility/apps/secops/talosctl-oidc/app/external-secret.yaml`
- Create: `kubernetes/utility/apps/secops/talosctl-oidc/app/helm-release.yaml`
- Create: `kubernetes/utility/apps/secops/talosctl-oidc/app/kustomization.yaml`
- Create: `kubernetes/utility/apps/secops/talosctl-oidc/flux-sync.yaml`

- [ ] **Step 1: Create directory**

```bash
mkdir -p kubernetes/utility/apps/secops/talosctl-oidc/app
```

- [ ] **Step 2: Write external-secret.yaml**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name talosctl-oidc-ca
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
        ca.crt: "{{ .ca_crt }}"
        ca.key: "{{ .ca_key }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/utility/secops/talosctl-oidc
```

- [ ] **Step 3: Write helm-release.yaml**

Replace `<CLIENT_ID>` with the Client ID from Pocket-ID.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app talosctl-oidc
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 5.0.1
      sourceRef:
        kind: HelmRepository
        name: bjw-s-charts
        namespace: flux-system
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
    global:
      createDefaultServiceAccount: false
    controllers:
      talosctl-oidc:
        containers:
          app:
            image:
              repository: ghcr.io/qjoly/talosctl-oidc-server
              tag: 0.0.4@sha256:ff55155e0f0af646239815bc3e015cb22cfaf05472b0a5e58dc8c22b12a60baa
            command: ["/talosctl-oidc", "serve"]
            env:
              TALOSCTL_OIDC_ISSUER_URL: https://id.techtales.io
              TALOSCTL_OIDC_CLIENT_ID: <CLIENT_ID>
              TALOSCTL_OIDC_ENDPOINTS: "192.168.100.31"
              TALOSCTL_OIDC_CERT_TTL: 60m
              TALOSCTL_OIDC_ROLES: os:reader
              TALOSCTL_OIDC_LISTEN: ":8443"
              TALOSCTL_OIDC_DATA_DIR: /data
              TALOSCTL_OIDC_CA_CERT: /config/ca.crt
              TALOSCTL_OIDC_CA_KEY: /config/ca.key
            ports:
              - name: https
                containerPort: &port 8443
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              runAsNonRoot: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 10m
                memory: 32Mi
        pod:
          securityContext:
            runAsUser: 65534
            runAsGroup: 65534
            runAsNonRoot: true
    defaultPodOptions:
      securityContext:
        fsGroup: 65534
        fsGroupChangePolicy: OnRootMismatch
    service:
      app:
        controller: *app
        type: LoadBalancer
        ports:
          https:
            port: 8443
    persistence:
      config:
        type: secret
        name: talosctl-oidc-ca
        globalMounts:
          - path: /config
            readOnly: true
      data:
        type: emptyDir
        globalMounts:
          - path: /data
```

- [ ] **Step 4: Write kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./external-secret.yaml
  - ./helm-release.yaml
```

- [ ] **Step 5: Write flux-sync.yaml**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app talosctl-oidc
spec:
  targetNamespace: secops
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/utility/apps/secops/talosctl-oidc/app
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
```

---

### Task 3: Main cluster — create deployment files

**Files:**

- Create: `kubernetes/main/apps/secops/talosctl-oidc/app/external-secret.yaml`
- Create: `kubernetes/main/apps/secops/talosctl-oidc/app/helm-release.yaml`
- Create: `kubernetes/main/apps/secops/talosctl-oidc/app/kustomization.yaml`
- Create: `kubernetes/main/apps/secops/talosctl-oidc/flux-sync.yaml`

- [ ] **Step 1: Create directory**

```bash
mkdir -p kubernetes/main/apps/secops/talosctl-oidc/app
```

- [ ] **Step 2: Write external-secret.yaml**

Same structure as utility but different OpenBao path:

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: &name talosctl-oidc-ca
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
        ca.crt: "{{ .ca_crt }}"
        ca.key: "{{ .ca_key }}"
  dataFrom:
    - extract:
        key: infra/kubernetes/main/secops/talosctl-oidc
```

- [ ] **Step 3: Write helm-release.yaml**

Replace `<CLIENT_ID>` with the same Pocket-ID Client ID. Note the different endpoints (3 control plane IPs).

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app talosctl-oidc
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 5.0.1
      sourceRef:
        kind: HelmRepository
        name: bjw-s-charts
        namespace: flux-system
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
    global:
      createDefaultServiceAccount: false
    controllers:
      talosctl-oidc:
        containers:
          app:
            image:
              repository: ghcr.io/qjoly/talosctl-oidc-server
              tag: 0.0.4@sha256:ff55155e0f0af646239815bc3e015cb22cfaf05472b0a5e58dc8c22b12a60baa
            command: ["/talosctl-oidc", "serve"]
            env:
              TALOSCTL_OIDC_ISSUER_URL: https://id.techtales.io
              TALOSCTL_OIDC_CLIENT_ID: <CLIENT_ID>
              TALOSCTL_OIDC_ENDPOINTS: "192.168.100.101,192.168.100.102,192.168.100.103"
              TALOSCTL_OIDC_CERT_TTL: 60m
              TALOSCTL_OIDC_ROLES: os:reader
              TALOSCTL_OIDC_LISTEN: ":8443"
              TALOSCTL_OIDC_DATA_DIR: /data
              TALOSCTL_OIDC_CA_CERT: /config/ca.crt
              TALOSCTL_OIDC_CA_KEY: /config/ca.key
            ports:
              - name: https
                containerPort: &port 8443
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              runAsNonRoot: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 10m
                memory: 32Mi
        pod:
          securityContext:
            runAsUser: 65534
            runAsGroup: 65534
            runAsNonRoot: true
    defaultPodOptions:
      securityContext:
        fsGroup: 65534
        fsGroupChangePolicy: OnRootMismatch
    service:
      app:
        controller: *app
        type: LoadBalancer
        ports:
          https:
            port: 8443
    persistence:
      config:
        type: secret
        name: talosctl-oidc-ca
        globalMounts:
          - path: /config
            readOnly: true
      data:
        type: emptyDir
        globalMounts:
          - path: /data
```

- [ ] **Step 4: Write kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./external-secret.yaml
  - ./helm-release.yaml
```

- [ ] **Step 5: Write flux-sync.yaml**

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app talosctl-oidc
spec:
  targetNamespace: secops
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/main/apps/secops/talosctl-oidc/app
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
```

---

### Task 4: Register in parent kustomizations

**Files:**

- Modify: `kubernetes/utility/apps/secops/kustomization.yaml`
- Modify: `kubernetes/main/apps/secops/kustomization.yaml`

- [ ] **Step 1: Register utility cluster deployment**

Add `./talosctl-oidc/flux-sync.yaml` to the resources list in `kubernetes/utility/apps/secops/kustomization.yaml`:

```yaml
- ./pocket-id/flux-sync.yaml
- ./talosctl-oidc/flux-sync.yaml
```

- [ ] **Step 2: Register main cluster deployment**

Add `./talosctl-oidc/flux-sync.yaml` to the resources list in `kubernetes/main/apps/secops/kustomization.yaml`:

```yaml
- ./external-secrets/flux-sync.yaml
- ./talosctl-oidc/flux-sync.yaml
```

---

### Task 5: Deploy and verify

- [ ] **Step 1: Commit and push changes**

```bash
git add kubernetes/main/apps/secops/talosctl-oidc/ \
        kubernetes/utility/apps/secops/talosctl-oidc/ \
        kubernetes/main/apps/secops/kustomization.yaml \
        kubernetes/utility/apps/secops/kustomization.yaml
git commit -m "feat: deploy talosctl-oidc for Pocket-ID authenticated read-only Talos access"
git push
```

Flux will pick up the changes automatically. To force a sync:

```bash
flux reconcile kustomization talosctl-oidc -n secops
```

- [ ] **Step 2: Verify pods are running**

```bash
kubectl get pods -n secops -l app.kubernetes.io/name=talosctl-oidc
```

- [ ] **Step 3: Check service and get LoadBalancer IP**

```bash
kubectl get svc -n secops -l app.kubernetes.io/name=talosctl-oidc
```

Expected output (for utility cluster — main will have a different IP):

```
NAME             TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)          AGE
talosctl-oidc    LoadBalancer   10.43.x.x      192.168.100.x     8443:3xxxx/TCP   1m
```

- [ ] **Step 4: Test the server health endpoint**

```bash
curl -k https://<EXTERNAL-IP>:8443/healthz
```

Expected: `200 OK`

- [ ] **Step 5: Retrieve the server CA for client use**

```bash
curl -k https://<EXTERNAL-IP>:8443/ca > server-ca.pem
```

Save this file for the client setup.

---

### Task 6: Client setup instructions

- [ ] **Step 1: Install talosctl-oidc CLI**

```bash
curl -fsSL https://raw.githubusercontent.com/qjoly/talosctl-oidc/main/install.sh | sh
```

- [ ] **Step 2: Login to main cluster**

```bash
talosctl-oidc login \
  --provider https://id.techtales.io \
  --client-id <CLIENT_ID> \
  --server https://<MAIN_LB_IP>:8443 \
  --server-ca main-server-ca.pem \
  --context-name main-reader
```

- [ ] **Step 3: Login to utility cluster**

```bash
talosctl-oidc login \
  --provider https://id.techtales.io \
  --client-id <CLIENT_ID> \
  --server https://<UTILITY_LB_IP>:8443 \
  --server-ca util-server-ca.pem \
  --context-name utility-reader
```

- [ ] **Step 4: Verify read-only access**

```bash
talosctl --context main-reader version
talosctl --context main-reader get members

talosctl --context utility-reader version
talosctl --context utility-reader get members
```

- [ ] **Step 5: Verify write operations are denied**

```bash
talosctl --context main-reader reboot
# Expected: ERROR (os:reader cannot reboot)
```
