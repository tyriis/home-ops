---
status: accepted
date: 2026-10-09
decision-makers: [tyriis]
---

# Adopt the RHDH community image as the Backstage distribution

## Context and Problem Statement

The custom-built Backstage image `harbor.techtales.io/library/techtales/backstage:v0.2.2` is gone:
its source repo never existed on GitHub, so the build pipeline, the Dockerfile, and the plugin set
are unrecoverable. The deployment in `kubernetes/main/apps/backstage/` is unsynced (flux-sync
commented out) and waits for a replacement. Recovered requirements: Pocket-ID OIDC sign-in,
TechDocs with contrib addons and mermaid, GitOps-managed, no cluster snowflakes.

The first planning pass assumed the official `ghcr.io/backstage/backstage` image "ships the dynamic
plugins framework". That premise was verified false against the published 1.55.2 image: it is a
plain create-app build (statically compiled plugins, no dynamic-plugins layer, no feature loader,
no python for the TechDocs builder) and its own OCI label states "there is no way to install
additional plugins". Any upstream path to extra plugins (OIDC module, TechDocs addons, mermaid)
requires a custom backend/app build — exactly the failure mode that lost v0.2.2.

## Decision Drivers

- No custom image build, no Dockerfile, no fork — a build we host is a build we can lose again.
- Plugin set must be changeable by GitOps config alone (add/enable plugins via manifests).
- Pocket-ID OIDC (fork-agnostic), TechDocs, mermaid, contrib addons.
- Digest-pinned images + Renovate (repo convention), GitOps-first.
- Home-ops scale: one instance, SQLite acceptable for iteration 1.

## Considered Options

- **`quay.io/rhdh-community/rhdh` (RHDH community image), digest-pinned, with its
  `install-dynamic-plugins` init container and a default-deny `dynamic-plugins.yaml`** — _chosen_
- Official `ghcr.io/backstage/backstage:1.55.2` with compiled-in plugins only
- Thin custom image (COPY plugins / add feature loader)
- Full custom app build (the v0.2.2 pattern)

## Decision Outcome

Chosen option: **RHDH community image**. It is the only published image that satisfies the whole
constraint set simultaneously: no build at all, dynamic backend AND frontend plugins from OCI
artifacts, config-driven sign-in, and a bundled TechDocs builder (python venv with
`mkdocs-techdocs-core` in the image).

Concrete parameters:

- Image `quay.io/rhdh-community/rhdh:1.10.5@sha256:ef7b9c8278e3ec2fb329ae1bb889bcce274411c7681e38e9e1743ef8a3e8b0f3`
  (manifest-list digest verified against the Quay API on 2026-10-09; the community repo has no
  `latest` tag, floating `1.10` moves under us — pin z-tags + digests).
- Catalog index `quay.io/rhdh/plugin-catalog-index:1.10@sha256:1592a52385dfc32fe772ded2897aa1455252fb33ae424d6f173b0b4673409059`
  — known and pinned, available if we ever switch the manifest to `includes:`/`{{inherit}}`;
  iteration 1 does not use it (default-deny, no registry round-trip at boot).
- RHDH 1.10 embeds Backstage 1.49.4 — the core line lags the official image (~1.55). Accepted:
  the features we need exist in 1.10; third-party plugin compatibility is enforced by the
  host-`frontend-plugin-api` version rule at packaging time.
- Third-party frontend addons (mermaid) are packaged by the documented RHDH CLI
  (`@red-hat-developer-hub/cli plugin package`) and pushed to Harbor as OCI artifacts — the same
  loading mechanism as everything else.
- Deployed via the existing app-template v5 HelmRelease (init container + shared emptyDir), not
  the rhdh-chart, to keep repo conventions; the chart is the reference for pod layout.

### Consequences

- Positive: plugin changes are ConfigMap edits; image + plugin artifacts are digest-pinned and
  Renovate-bumpable; no build infra to maintain; lost-image scenario becomes
  "change one `image:` value".
- Negative (accepted): the enabling/sign-in configuration schema is the RHDH fork, not upstream
  `app-config` keys — portability back to a vanilla upstream build later costs a config rewrite
  (no code). The 1.10 line lags upstream Backstage; RHDH 2.x (Backstage 1.5x) is a deliberate
  migration event, not a tag bump.
- Revisit triggers: RHDH 2.x stable release (evaluate migration); need for bespoke shell UI
  (branded React code) → returns a custom build to scope; TechDocs requirement that needs
  build-time plugins (Kroki) forces a separate mkdocs builder image (still no Backstage build).

## Pros and Cons of the Options

### Official image `ghcr.io/backstage/backstage:1.55.2`

- Pro: newest Backstage core, zero fork surface.
- Killed by: OIDC provider module, TechDocs addons, and every third-party plugin need a custom
  build (no loader compiled in); no python in the image → no local TechDocs builder; contradicts
  the primary driver.

### Thin custom image / full custom build

- Pro: exact plugin set, upstream schema.
- Killed by: re-creates the rebuild-per-change cycle and the ownership problem that lost v0.2.2;
  the only scenario that still justifies a build (bespoke shell) is a non-goal.
