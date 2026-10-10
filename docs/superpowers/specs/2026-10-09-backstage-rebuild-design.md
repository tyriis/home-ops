# Backstage rebuild on the RHDH community image — implementation spec

Date: 2026-10-09
Ticket: #10917
ADR: docs/decisions/0015-adopt-rhdh-community-image.md

Replaces the lost custom image `harbor.techtales.io/library/techtales/backstage:v0.2.2` with the
no-build dynamic distribution `quay.io/rhdh-community/rhdh` (ADR-0015). Follows existing repo
conventions verbatim — every pattern here is copied from a working example in this repo (paths
cited). Scope is manifests only (GitOps-first); a short list of manual steps on external systems
(Terraform/Pocket-ID, OpenBao, Harbor) is section 10.

## 1. Layout and naming

Everything stays inside the existing app folder; no new namespaces or Kustomizations.

| Resource                | Name/value                                                | Notes                                    |
| ----------------------- | --------------------------------------------------------- | ---------------------------------------- |
| HelmRelease             | `backstage` (ns `backstage`)                              | unchanged, app-template 5.2.1            |
| image                   | `quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c8278e3…` | manifest-list digest verified 2026-10-09 |
| initContainer           | `dynamic-plugins`                                         | same image, installer mode               |
| ConfigMap               | `app-config`                                              | adds `dynamic-plugins.yaml` file         |
| PVC                     | `backstage-data`, 5 Gi, `ceph-block`                      | SQLite file + local-published docs       |
| emptyDir                | `dynamic-plugins-root`                                    | rebuilt by installer every boot          |
| Secret (ExternalSecret) | `backstage-secrets`                                       | fields swap Google → Pocket-ID OIDC      |
| Route                   | `backstage.techtales.io` via envoy https                  | unchanged                                |

The dist folder names of bundled plugins (`./dynamic-plugins/dist/...`) and the
`pluginConfig`/scalprum keys used by the manifests are read from the pinned image itself
(`docker run --rm --entrypoint ls … dynamic-plugins/dist` plus its
`dynamic-plugins.default.yaml`) during plan Task 1 — the docs below quote the expected values but
Task 1 overrides them: `backstage-plugin-techdocs`, `backstage-plugin-techdocs-backend-dynamic`,
`backstage-plugin-techdocs-module-addons-contrib`. Probes change: RHDH serves
`/.backstage/health/v1/liveness` and `/readiness` (not the old image's `/health`); the plan carries
the new paths with a startup probe for the cold start.

## 2. Sync wiring

Uncomment `- ./backstage/flux-sync.yaml` in `kubernetes/main/apps/backstage/kustomization.yaml` —
the app is currently disabled and would otherwise never reconcile. Existing `flux-sync.yaml`
(`dependsOn: external-secrets-stores`) is otherwise unchanged.

## 3. Storage

Precedent: pocket-id app (`kubernetes/utility/apps/secops/pocket-id/app/helm-release.yaml`) for
`initContainers` + `advancedMounts`, immich app (`kubernetes/main/apps/media/immich/app/helm-release.yaml`)
for `defaultPodOptions.securityContext` and extra-PVC layout.

- Pod `securityContext` (via `defaultPodOptions`): `runAsNonRoot: true`, `runAsUser/runAsGroup/fsGroup: 1001`.
  The RHDH image runs as uid 1001 (verified in image config; NOT 1000 as in the draft plan) —
  SQLite and the TechDocs publisher directory must be writable by 1001.
- PVC `backstage-data` (`ceph-block`, RWO, 5 Gi) mounted at `/var/backstage-data` on the `app`
  container. Block storage, not `nfs-truenas`: SQLite over NFS locking is a known failure mode.
- emptyDir `dynamic-plugins-root`: mounted at `/dynamic-plugins-root` (init container) and
  `/opt/app-root/src/dynamic-plugins-root` (app container) via `advancedMounts`. Contents are
  re-extracted from digests on every boot — a PVC here would only cache staleness.
- ConfigMap `app-config` gains a second file `dynamic-plugins.yaml`; the init container mounts it
  at its required fixed path `/opt/app-root/src/dynamic-plugins.yaml` (`subPath`), the app
  container mounts the whole ConfigMap directory at `/app-config`.

## 4. Dynamic plugins

Loader: RHDH's `install-dynamic-plugins` init container (same image, command
`./install-dynamic-plugins.sh /dynamic-plugins-root`), the layout mirrored from rhdh-chart
release-1.10. The installer is the mechanism — no custom `oras` sidecar.

Policy: default-deny. `dynamic-plugins.yaml` has **no `includes:`** line, so nothing from
RHDH's 15-plugin default set loads unless we list it; `CATALOG_INDEX_IMAGE` is not set (no
registry round-trip at boot) and the plugin root is pinned explicitly with
`dynamicPlugins.rootDirectory` in the app-config. Iteration 1 enable list — everything else
(adoption insights, quickstart, segment analytics, dynamic home page, global header, search UI
dynamic wrappers, …) stays off:

| Enable (local dist unless noted)                                               | Why                                                               |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| `./dynamic-plugins/dist/backstage-plugin-techdocs`                             | TechDocs reader UI                                                |
| `./dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic`             | TechDocs builder/publisher backend                                |
| `./dynamic-plugins/dist/backstage-plugin-techdocs-module-addons-contrib`       | ReportIssue, TextSize, LightBox via `pluginConfig.techdocsAddons` |
| `oci://harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:<ver>@<digest>` | mermaid in TechDocs (see 5)                                       |

Catalog, scaffolder, kubernetes, search and the auth provider modules are statically compiled into
the image (verified in `node_modules` of 1.10.5) — config, not plugins. Task 1 double-checks the
one risk in that claim: if the image's `dynamic-plugins/dist` contains an
`…-oidc-provider-dynamic` wrapper (auth modules historically ship as bundled-but-disabled
wrappers), the manifest gains a fourth local enable entry for it. No `.npmrc` mount is needed: the
enable list is local-dist + OCI only, no npm-sourced packages.
`dynamic-plugins.yaml` is a ConfigMap file (KBs), well under the 1 MB etcd limit; the existing
`reloader.stakater.com/auto: "true"` annotation restarts the pod when it changes, which is what
plugin changes need.

## 5. Third-party plugin artifacts (Harbor OCI)

Upstream npm ships the mermaid addon (`backstage-plugin-techdocs-addon-mermaid`) without a dynamic
bundle; the documented path for third-party addons is: `npx @red-hat-developer-hub/cli plugin
package --tag harbor.techtales.io/rhdh-plugins/techdocs-addon-mermaid:<ver>` (builds the bundle,
pushes it as an OCI artifact) → installer entry `oci://…`. This keeps Harbor OCI as the artifact
store (as decided in the draft plan) but uses RHDH's own tooling — no new infra.

- Version rule: highest addon release whose `@backstage/frontend-plugin-api` dependency range
  resolves against the host's copy (`/opt/app-root/src/node_modules/@backstage/frontend-plugin-api`
  in 1.10.5, a 1.49.x core). Checked at Task 1. The `oci://` package pins tag **and digest**
  (`…techdocs-addon-mermaid:<addon-ver>@sha256:…`), tag = upstream addon version, digest recorded
  when the artifact is pushed (section 10) — matching the repo's image-digest convention.
  Module Federation against a mismatched core is the main breakage mode (risk R5).
- Harbor project `rhdh-plugins` is **public-read** so skopeo inside the installer pulls
  anonymously — no `auth.json` mount in iteration 1 (push needs credentials, section 10).
- Publishing repo: new GitHub repo `techtales-io/backstage-plugins` — one Taskfile target + CI
  (build → `docker push`) per addon. Version bumps bump the tag **and** the digest in the
  manifest (Renovate entry in plan Task 6).

## 6. Auth — Pocket-ID OIDC

Pocket-ID issuer `https://id.techtales.io` (source: `kubernetes/components/envoy-pocketid/security-policy.yaml`).
The `oidc` provider module is compiled into the image; sign-in is pure config, no custom
`SignInPageBlueprint` code.

- `auth.providers.oidc.production`: `metadataUrl: https://id.techtales.io/.well-known/openid-configuration`,
  `clientId/clientSecret` from the Secret, `prompt: auto`,
  `signIn.resolvers: [emailLocalPartMatchingUserEntityName]` (creates a User entity on first
  sign-in — the catalog has no User entities today, verified: no `kind: User` in `docs/backstage`).
- `auth.session.secret: ${AUTH_SESSION_SECRET}` — new, mandatory (backend refuses to boot
  without it).
- Top-level `signInPage: oidc` renders the sign-in button (config, not code).
- Callback/redirect URLs to register in Pocket-ID:
  `https://backstage.techtales.io/api/auth/oidc/handler/frame` and
  `https://backstage.techtales.io/api/auth/oidc/redirect` (register both; the second covers the
  experimental redirect flow).
- Permission framework: left default-off (`PERMISSION_ENABLED` unset, verified default in the
  image's app-config). No RBAC plugin, no group claims, single-admin homelab posture. Revisit
  with `backstage-community-plugin-rbac` + Pocket-ID groups if lock-in ever bites.
- The draft plan's `enableExperimentalRedirectFlow` legacy key is dropped (old-system auth
  config, ineffective in 1.10).

## 7. TechDocs

The image ships `/opt/techdocs-venv` (mkdocs + `mkdocs-techdocs-core`, verified in the 1.10.5
layer) with `PATH` pre-set, so the local builder works — but the in-image default config is
`builder: external`, so our config must set `builder: local`, `generator: { runIn: local }`.
Publisher: `type: local`, publish directory `/var/backstage-data/techdocs` (PVC) — key name
(`publishPath` vs `publishDirectory` across versions) is pinned against the bundled
`dist/.config-schema.json` at Task 1.

Correction to the draft plan: the local generator runs `mkdocs` from the venv and does **not**
pip-install `docs/requirements.txt` from the docs repo (verified against the 1.49.x generator
code). The later Kroki step (N1) therefore needs a builder image with `mkdocs-kroki-plugin`
pre-installed (or CI-side generation) — a docs-side image, still no Backstage build. Kroki and
mermaid-via-Kroki stay next-steps exactly as the draft plan scoped them.

## 8. Database

SQLite file (draft-plan decision D3 kept, one syntax fix):
`backend.database.client: better-sqlite3`, `connection: /var/backstage-data/db/backstage.db` —
bare path (the `better-sqlite3:` URI prefix from the draft plan is not the connector's format),
parent dir auto-created, no `:memory:` so a pod restart keeps the catalog. No LiteStream; the
data is re-derivable. Upgrade path when needed: dedicated CNPG Cluster under
`backstage/database/` following immich's `database/` folder (cluster + initdb secret +
Barman ObjectStore + ScheduledBackup), a one-line app-config change + ExternalSecret fields then.

## 9. Config: app-config.production.yaml

Carried over unchanged: `baseUrl`/`env`, catalog locations and rules, `reading.allow`, csp
(`img-src` gains `data:` for inline-SVG diagrams), TechDocs section shape. Changed/added:
`auth` block (section 6), `auth.session.secret`, `backend.database` file path (section 8),
TechDocs overrides (section 7). The stale `file: /docs/backstage/catalog-info.yaml` location is
dropped — that mount died with the old image. ConfigMap keeps
`kustomize.toolkit.fluxcd.io/substitute: disabled`.

## 10. Manual / external prerequisites (NOT repo work)

1. `terraform-pocket-id`: add `data/clients/backstage.yaml` (`kind: PocketIdClient`, callbackUrls
   from section 6, `launchUrl: https://backstage.techtales.io`, `groups: [admins, users]`,
   `pkce: false` — confidential client with secret); apply via Atlantis.
2. OpenBao: update key `infra/kubernetes/main/backstage/backstage` — remove `AUTH_GOOGLE_*`,
   add `AUTH_OIDC_CLIENT_ID`/`AUTH_OIDC_CLIENT_SECRET` (copy from
   `infra/pocketid/clients/backstage`), new random `AUTH_SESSION_SECRET` (≥32 bytes).
3. Harbor: create project `rhdh-plugins` (public read) + robot account for CI pushes.
4. Create GitHub repo `techtales-io/backstage-plugins` (addon bundle CI), push the mermaid addon
   artifact, and record its digest for the manifest entry.
5. Route/DNS/envoy: nothing — existing hostname, parentRefs, external-dns annotation stand.

## 11. Non-goals

RBAC/permissions, custom app shell/branding beyond `app` config keys, Harbor pull-through mirror
for quay.io (direct quay.io pull in iteration 1; add a Harbor proxy if ghcr/quay egress ever
bites), LiteStream/backup of the SQLite DB, CNPG, Kroki, Kubernetes-runtime plugins beyond the
static set, rhdh-chart adoption, search UI (if the search frontend turns out to be a dynamic
wrapper rather than compiled in, a disabled search page in iteration 1 is accepted, not a bug).

## 12. Risks

- R1: bundled dist folder names and the TechDocs publisher key are re-verified against the pinned
  digest in plan Task 1 before any manifest is written.
- R2: `mkdocs-kroki-plugin` 0.8.1 has a TechDocs light/dark duplication regression (GitHub #70) —
  only relevant at N1 time; pin known-good + documented CSS fallback.
- R3: RHDH fork config schema locks us to the RHDH/janus enabling keys; reverting to a vanilla
  upstream build later costs a config rewrite. Accepted (ADR-0015).
- R4: RHDH 1.10 tracks a ~6-minor-lagging Backstage core (1.49.4). Accepted for iteration 1;
  RHDH 2.x is a separate migration project.
- R5: Module Federation drift if the mermaid addon's core differs from the host's — prevented by
  the section 5 version rule; symptom is a broken TechDocs reader, fixed by pinning an older
  addon artifact.
- R6: first sign-in auto-creates a User entity named after the email local part; odd local parts
  create odd entity names. Cosmetic; fixable later with a seeded User + explicit resolver.
