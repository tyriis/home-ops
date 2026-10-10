# Backstage rebuild on the RHDH community image — Implementation Plan

> **For agentic workers:** Execute task-by-task; each task ends with a commit. Commits follow
> repo GIT_COMMIT rules: `<type>(<scope>): <desc> #10917` — scope is `backstage`. Implementers
> are authorized to add lint/format fixes (prettier/yamllint/markdownlint) required by CI, and to
> apply the pinned-value corrections found by the Task 1 image inspection (dist folder names,
> publisher key, addon version) everywhere they appear.

**Goal:** Deploy Backstage from the no-build RHDH community image (`quay.io/rhdh-community/rhdh`,
latest stable 1.10.5) with Pocket-ID OIDC sign-in, dynamic TechDocs (contrib addons + mermaid via
Harbor OCI artifact), SQLite-on-PVC, and the Flux sync re-enabled.

**Architecture:** Single app-template v5 HelmRelease. An `install-dynamic-plugins` init container
(same RHDH image) reads a default-deny `dynamic-plugins.yaml` from the app ConfigMap and extracts
plugins into an emptyDir the backend loads at boot. App behavior is pure app-config: OIDC module,
TechDocs local builder (venv ships in the image) and local publisher, better-sqlite3 on a block
PVC. ADR-0015 records why this distribution replaced the lost custom build.

**Spec:** `docs/superpowers/specs/2026-10-09-backstage-rebuild-design.md` (Ticket #10917) — read
it first; this plan argues from it. ADR: `docs/decisions/0015-adopt-rhdh-community-image.md`.

**Tech:** app-template chart 5.2.1, rhdh image
`1.10.5@sha256:ef7b9c8278e3ec2fb329ae1bb889bcce274411c7681e38e9e1743ef8a3e8b0f3`,
ExternalSecrets/OpenBao (`ClusterSecretStore openbao-backend`), envoy Gateway route (unchanged).

**Manual prereqs (spec §10) are done by the human before the flux-sync task:** Terraform
`PocketIdClient` applied via Atlantis, OpenBao key updated, Harbor `rhdh-plugins` project +
artifact pushed (Task 5), `techtales-io/backstage-plugins` repo created. Task 6 lists them again.

**Conventions:** manifests live in `kubernetes/main/apps/backstage/backstage/app/`. All YAML
starts with `---` and keeps the existing `# yaml-language-server:` schema header. Re-runs of
`task lint:yaml` / `task lint:prettier` must stay clean. No cluster apply — GitOps-first, Flux
reconciles after merge.

## Global Constraints

- Image pinned by z-tag + manifest-list digest, both from ADR-0015:
  `quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c8278e3ec2fb329ae1bb889bcce274411c7681e38e9e1743ef8a3e8b0f3`
- No new apps/namespaces/Kustomizations beyond editing the existing backstage folder; no new
  Helm chart; no rhdh-chart.
- Pocket-ID issuer is `https://id.techtales.io`; callback
  `https://backstage.techtales.io/api/auth/oidc/handler/frame`; OpenBao key
  `infra/kubernetes/main/backstage/backstage` on `ClusterSecretStore openbao-backend`.
- Container runs as uid/gid 1001; all writable paths need fsGroup 1001.
- SQLite connection is a bare path (no `better-sqlite3:` prefix).
- Health probes use RHDH paths `/.backstage/health/v1/liveness` / `/readiness` (the old image's
  `/health` does not exist here); a startup probe budgets ~120 s cold start.
- Memory limit 2 Gi (RHDH + a co-located python TechDocs builder), 512 Mi request.
- The OCI addon package pins tag AND digest; the digest comes from the Task 5 push.
- Never edit `flux-sync.yaml` itself — only uncomment its line in the parent Kustomization.

---

### Task 1: Pin verification against the image (no repo changes)

**Files:**

- Read only; results are written into the scratch file `.task1-findings.md` (repo root, deleted in
  Task 6) that later tasks consume.

- [ ] **Step 1: List the bundled dynamic plugin dist folders**

```sh
docker run --rm --entrypoint ls \
  quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c8278e3ec2fb329ae1bb889bcce274411c7681e38e9e1743ef8a3e8b0f3 \
  dynamic-plugins/dist
```

Record the exact folder names for: techdocs frontend, techdocs backend, techdocs contrib addons.
Expected (adjust manifests in Tasks 2/5 if different): `backstage-plugin-techdocs`,
`backstage-plugin-techdocs-backend-dynamic`,
`backstage-plugin-techdocs-module-addons-contrib`.

- [ ] **Step 2: Confirm the TechDocs venv and the publisher config key**

```sh
docker run --rm --entrypoint sh \
  quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  -c 'ls /opt/techdocs-venv/bin/mkdocs && cat dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic/dist/.config-schema.json | jq ".properties.techdocs.properties.publisher.properties.local"'
```

Record whether the local publisher key is `publishPath` or `publishDirectory` and use that key in
Task 2. Expected: venv exists; key is `publishPath`.

- [ ] **Step 3: Determine the host frontend-plugin-api line and pick the mermaid addon version**

```sh
docker run --rm --entrypoint cat \
  quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  node_modules/@backstage/frontend-plugin-api/package.json | jq .version
npm view backstage-plugin-techdocs-addon-mermaid versions --json
```

Pick the highest addon version whose `@backstage/frontend-plugin-api` dependency range contains
the host version (`npm view backstage-plugin-techdocs-addon-mermaid@<v> dependencies`). Record the
chosen version for Task 5.

- [ ] **Step 4: Confirm installer + probe paths and the auth-module packaging**

```sh
docker run --rm --entrypoint sh quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  -c 'test -x install-dynamic-plugins.sh && echo installer-ok'
docker run --rm --entrypoint ls quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  dynamic-plugins/dist | grep -i auth || echo "no auth dist wrappers"
docker run --rm --entrypoint sh quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  -c 'grep -o "/.backstage/health/v1/[a-z]*" -r node_modules/@backstage/plugin-app-backend/dist 2>/dev/null | sort -u'
```

If an auth dist wrapper exists (e.g. `…-auth-backend-module-oidc-provider-dynamic`), the
`dynamic-plugins.yaml` from Task 2 gains a fourth local enable entry — otherwise sign-in
404s silently. Record wrapper names.

- [ ] **Step 5: Extract the exact pluginConfig keys from the image's own default manifest**

```sh
docker run --rm --entrypoint cat quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c82... \
  dynamic-plugins.default.yaml | sed -n '/techdocs/,/^  - package/p'
```

Copy verbatim from the image: the scalprum/pluginId key for the contrib-addons package, the
`techdocsAddons` block shape, and how the default set lists these packages (it may use
`ref://`/`enabled:` in 1.10.5 — translate to `disabled: false` form for our no-includes
manifest). For the unscoped mermaid addon, Task 5 copies its key from the packaged bundle's
`package.json` (`scalprum.name` / `backstage.role`), never guesses it.

- [ ] **Step 6: Write findings** — dist names, publisher key, addon version, installer-ok, auth
      wrapper status, probe paths, verbatim pluginConfig keys into `.task1-findings.md`. No commit.

---

### Task 2: App config + dynamic plugin manifest

**Files:**

- Modify: `kubernetes/main/apps/backstage/backstage/app/resources/app-config.production.yaml`
- Create: `kubernetes/main/apps/backstage/backstage/app/resources/dynamic-plugins.yaml`
- Modify: `kubernetes/main/apps/backstage/backstage/app/kustomization.yaml` (ConfigMap files list)

- [ ] **Step 1: Rewrite `resources/app-config.production.yaml`** (publisher key per Task 1)

```yaml
---
app:
  baseUrl: ${BASE_URL}
  title: TechTales Backstage

# Explicit plugin root — no reliance on the relative-path default.
dynamicPlugins:
  rootDirectory: /opt/app-root/src/dynamic-plugins-root

# Pocket-ID OIDC via the oidc module compiled into the RHDH image.
auth:
  environment: production
  session:
    secret: ${AUTH_SESSION_SECRET}
  providers:
    oidc:
      production:
        metadataUrl: https://id.techtales.io/.well-known/openid-configuration
        clientId: ${AUTH_OIDC_CLIENT_ID}
        clientSecret: ${AUTH_OIDC_CLIENT_SECRET}
        prompt: auto
        signIn:
          resolvers:
            - resolver: emailLocalPartMatchingUserEntityName

signInPage: oidc

# Local builder: /opt/techdocs-venv (mkdocs + mkdocs-techdocs-core) ships in the image.
techdocs:
  builder: local
  generator:
    runIn: local
  publisher:
    type: local
    local:
      publishPath: /var/backstage-data/techdocs

backend:
  baseUrl: ${BASE_URL}
  listen: ":7007"
  cors:
    origin: ${BASE_URL}
  csp:
    connect-src: ["'self'", "http:", "https:"]
    img-src: ["'self'", "data:", "https:"]
  # SQLite on the data PVC: catalog survives pod restarts; a lost PVC just re-ingests.
  database:
    client: better-sqlite3
    connection: /var/backstage-data/db/backstage.db
  reading:
    allow:
      - host: raw.githubusercontent.com
        path: /tyriis/locking-service/main/openapi.yaml

catalog:
  import:
    entityFilename: catalog-info.yaml
    pullRequestBranchName: backstage-integration
  rules:
    - allow: [Component, System, API, Resource, Location, User, Group, Domain]
  locations:
    - type: url
      target: https://github.com/tyriis/home-ops/blob/main/docs/backstage/catalog-info.yaml
    - type: url
      target: https://github.com/techtales-io/backstage-docs/blob/main/knowledge/catalog-info.yaml
```

- [ ] **Step 2: Create `resources/dynamic-plugins.yaml`** — default-deny (no `includes:`, no
      catalog index). The `plugins[].package` dist names, any auth-module wrapper entry (Task 1 Step
      4), and the `dynamicPlugins.frontend.<key>` scalprum names below are **transcribed from
      `.task1-findings.md`**, not typed from this doc; the block shows the expected shape:

```yaml
---
# Default-deny: nothing loads unless listed here. RHDH's own default set stays off.
plugins:
  - package: ./dynamic-plugins/dist/backstage-plugin-techdocs
    disabled: false
  - package: ./dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic
    disabled: false
  - package: ./dynamic-plugins/dist/backstage-plugin-techdocs-module-addons-contrib
    disabled: false
    pluginConfig:
      dynamicPlugins:
        frontend:
          backstage.plugin-techdocs-module-addons-contrib:
            techdocsAddons:
              - importName: ReportIssue
              - importName: TextSize
              - importName: LightBox
```

- [ ] **Step 3: Extend the ConfigMap generator** — add the second file under
      `configMapGenerator[0].files` in `app/kustomization.yaml`:

```yaml
- dynamic-plugins.yaml=./resources/dynamic-plugins.yaml
```

- [ ] **Step 4: Lint**

Run: `task lint:yaml && task lint:prettier` — Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add kubernetes/main/apps/backstage/backstage/app/resources/ kubernetes/main/apps/backstage/backstage/app/kustomization.yaml
git commit -m "feat(backstage): rebase app-config on RHDH with Pocket-ID OIDC #10917"
```

---

### Task 3: HelmRelease — image, installer init container, storage

**Files:**

- Modify: `kubernetes/main/apps/backstage/backstage/app/helm-release.yaml`

- [ ] **Step 1: Replace `values`** — keep the chart/`envFrom`/service/route blocks; **replace the
      probes block** (RHDH serves the app-backend health routes, not the old image's `/health`):

```yaml
probes:
  liveness: &probes
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /.backstage/health/v1/liveness
        port: &port 7007
      initialDelaySeconds: 0
      periodSeconds: 10
      timeoutSeconds: 1
      failureThreshold: 3
  readiness: *probes
  startup:
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /.backstage/health/v1/liveness
        port: 7007
      periodSeconds: 5
      failureThreshold: 24
```

(Startup budget ~120 s matches the rhdh-chart default; without it liveness kills RHDH mid-boot.
Verify both paths against the image in Task 1 Step 4 — the readiness route may be
`/.backstage/health/v1/readiness`, in which case use it for `readiness`.)

Apply these further deltas to `values`:

- Add at values level (precedent: immich app helm-release):

```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
    fsGroup: 1001
    fsGroupChangePolicy: OnRootMismatch
```

- Under `controllers.backstage` add (precedent: pocket-id app for `initContainers` +
  `advancedMounts`):

```yaml
initContainers:
  dynamic-plugins:
    image:
      repository: quay.io/rhdh-community/rhdh
      tag: 1.10.5@sha256:ef7b9c8278e3ec2fb329ae1bb889bcce274411c7681e38e9e1743ef8a3e8b0f3
    workingDir: /opt/app-root/src
    command:
      - ./install-dynamic-plugins.sh
    args:
      - /dynamic-plugins-root
```

- On `containers.app`: change image to the same repository/tag pair; add args (the RHDH
  entrypoint is exec-form, so these append after the image's own `--config` flags and win);
  raise memory (413 Mi was sized for a leaner build):

```yaml
args:
  - --config
  - /opt/app-root/src/dynamic-plugins-root/app-config.dynamic-plugins.yaml
  - --config
  - /app-config/app-config.production.yaml
resources:
  requests:
    cpu: 50m
    memory: 512Mi
  limits:
    memory: 2Gi
```

(The 2 Gi limit leaves room for the in-container python mkdocs child process spawned per
TechDocs render; the old 413 Mi was sized for a leaner build.)

- Replace `persistence` entirely (advancedMounts are keyed per container):

```yaml
persistence:
  config:
    type: configMap
    name: app-config
    advancedMounts:
      backstage:
        dynamic-plugins:
          - path: /opt/app-root/src/dynamic-plugins.yaml
            subPath: dynamic-plugins.yaml
            readOnly: true
        app:
          - path: /app-config
            readOnly: true
  dynamic-plugins:
    type: emptyDir
    advancedMounts:
      backstage:
        dynamic-plugins:
          - path: /dynamic-plugins-root
        app:
          - path: /opt/app-root/src/dynamic-plugins-root
  data:
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    storageClass: ceph-block
    size: 5Gi
    globalMounts:
      - path: /var/backstage-data
```

- [ ] **Step 2: Validate render** — `task lint:yaml && task lint:prettier`; if a local chart
      render is possible (`helm template` with the app-template 5.2.1 chart), confirm the pod spec has
      two containers mounting the emptyDir at their respective paths.

- [ ] **Step 3: Commit**

```sh
git add kubernetes/main/apps/backstage/backstage/app/helm-release.yaml
git commit -m "feat(backstage): run RHDH image with dynamic plugin installer #10917"
```

---

### Task 4: ExternalSecret — Pocket-ID OIDC + session secret

**Files:**

- Modify: `kubernetes/main/apps/backstage/backstage/app/external-secret.yaml`

- [ ] **Step 1: Swap template fields** (store + `dataFrom` key unchanged):

```yaml
data:
  AUTH_OIDC_CLIENT_ID: "{{ .AUTH_OIDC_CLIENT_ID }}"
  AUTH_OIDC_CLIENT_SECRET: "{{ .AUTH_OIDC_CLIENT_SECRET }}"
  AUTH_SESSION_SECRET: "{{ .AUTH_SESSION_SECRET }}"
  BASE_URL: "{{ .BASE_URL }}"
```

- [ ] **Step 2: Commit**

```sh
git add kubernetes/main/apps/backstage/backstage/app/external-secret.yaml
git commit -m "refactor(backstage): swap Google secrets for Pocket-ID OIDC and session #10917"
```

---

### Task 5: Mermaid addon OCI artifact (external repo + manifest entry)

**Files:**

- Create (external GitHub repo `techtales-io/backstage-plugins`): Taskfile + Actions workflow
- Modify: `kubernetes/main/apps/backstage/backstage/app/resources/dynamic-plugins.yaml`

- [ ] **Step 1: Human — publish the artifact** in `techtales-io/backstage-plugins`, addon version
      from Task 1 Step 3, tagged with that upstream version; capture the push digest for Step 2:

```sh
ADDON_VER=<ver-from-task-1>
npm pack backstage-plugin-techdocs-addon-mermaid@${ADDON_VER}
npx @red-hat-developer-hub/cli@latest plugin package \
  --tag harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:${ADDON_VER}
docker push harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:${ADDON_VER}
skopeo inspect --format '{{.Digest}}' \
  docker://harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:${ADDON_VER}
```

The repo's CI wraps exactly these steps (checkout, npm ci, package, push with the Harbor robot
account); the initial push may be manual. Record the digest and the packaged bundle's
`scalprum.name`/`backstage.role` from the bundle `package.json`.

- [ ] **Step 2: Append the plugin entry** to `resources/dynamic-plugins.yaml` — the scalprum key
      is copied from the packaged `package.json` (unscoped packages do NOT get dotted keys), and the
      package pins tag + digest:

```yaml
# Mermaid rendering in TechDocs — self-published RHDH dynamic bundle (techtales-io/backstage-plugins).
- package: oci://harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:<ADDON_VER>@<DIGEST>
  disabled: false
  pluginConfig:
    dynamicPlugins:
      frontend:
        backstage-plugin-techdocs-addon-mermaid:
          techdocsAddons:
            - importName: TechDocsMermaidAddon
```

- [ ] **Step 3: Commit**

```sh
git add kubernetes/main/apps/backstage/backstage/app/resources/dynamic-plugins.yaml
git commit -m "feat(backstage): render mermaid in TechDocs via Harbor OCI addon #10917"
```

---

### Task 6: Re-enable sync, Renovate wiring, validation sweep

**Files:**

- Modify: `kubernetes/main/apps/backstage/kustomization.yaml`
- Modify: `.github/renovate.json5`

- [ ] **Step 1: Confirm the spec §10 manual prereqs are done** (Pocket-ID client live in
      Atlantis-applied Terraform, OpenBao key holds the four fields, Harbor project + artifact
      pushed). Do not proceed to Step 2 otherwise.

- [ ] **Step 2: Uncomment the flux sync line** in `kubernetes/main/apps/backstage/kustomization.yaml`:

```yaml
resources:
  - ./namespace.yaml
  - ./backstage/flux-sync.yaml
```

- [ ] **Step 3: Renovate wiring** — read `.github/renovate.json5` first, then add (matching the
      file's existing structure): a docker-manager entry for `quay.io/rhdh-community/rhdh` with
      digest pinning, and a docker datasource entry for
      `harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid`.

- [ ] **Step 4: Sweep** — delete `.task1-findings.md`; run
      `task lint:yaml && task lint:prettier && task lint:markdown`. Expected: PASS.

- [ ] **Step 5: Commit**

```sh
git add kubernetes/main/apps/backstage/kustomization.yaml .github/renovate.json5
git commit -m "chore(backstage): re-enable Flux sync and add Renovate pins #10917"
```

**Ordering:** Tasks 1→2→3→4 are the repo spine; 5 needs a human push and can land any time
before 6; 6 last.

**Validation (post-merge, human/Flux — no cluster apply):**

1. Pod goes Ready; init container log shows the 4 plugins installed, nothing else.
2. `GET /api/dynamic-plugins-info/loaded-plugins` lists exactly the manifest set.
3. Sign-in page shows the Pocket-ID/OIDC button; a full login lands on the catalog; a User entity
   named after the email local part exists.
4. A home-ops TechDocs book renders with a mermaid fence and the TextSize/LightBox/ReportIssue
   controls.
5. Delete the pod — catalog and docs survive (SQLite + publisher on the PVC).
6. `kubectl get pvc backstage-data -n backstage` bound on `ceph-block`.
