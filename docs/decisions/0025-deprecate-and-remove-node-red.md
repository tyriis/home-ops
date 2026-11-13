---
status: accepted
date: 2026-11-13
decision-makers: [tyriis]
---

# Deprecate and remove Node-RED

## Context and Problem Statement

Node-RED has run on the main cluster since 2025-09-10 as the event-driven
automation runtime for home automation (`kubernetes/main/apps/home-automation/node-red`).
Since then the automations moved to Home Assistant native automations, and
anything that needs external orchestration belongs in n8n, which runs in the
same namespace.

The instance is no longer doing work. Its pod has been up since 2026-10-31 with
zero restarts and logs nothing but a failed reconnect to Home Assistant every
five seconds, so the flows are not executing. Three automation runtimes (Home
Assistant native, n8n, Node-RED) also mean three places to look when an
automation misbehaves.

## Decision Drivers

- One automation runtime per job; node-red duplicates Home Assistant native and
  n8n.
- A broken Home Assistant connection makes the deployment look healthy while
  doing nothing.
- `node-red.techtales.io` is a public HTTPS route to a low-code editor with
  cluster and Home Assistant reach; that surface is not needed.
- 247Mi of memory requests and a volsync pipeline (PVC, restic repo, OpenBao
  path) maintained for an idle service.

## Considered Options

- **Keep Node-RED** (status quo): maintains a broken integration and a public
  editor route for no automation value.
- **Deprecate only** (drop the route and homepage tile, keep the workload):
  keeps the image pin, PVC and backup pipeline alive for a service nobody uses.
- **Remove completely and delete the data** — chosen.

## Decision Outcome

Chosen option: **remove node-red from the main cluster and delete its data with
the change.** No retention window.

- Remaining automations live in Home Assistant native automations; items that
  need real orchestration go to n8n.
- No flows are migrated. The flow definitions were already stale (see the failed
  Home Assistant connection in the Context).
- Deleted with the app: HelmRelease, Flux Kustomization, Service, HTTPRoute,
  gitconfig ConfigMap, ExternalSecret and volsync objects.
- Deleted manually, because Flux does not prune them: PVC `node-red-data`
  (`kustomize.toolkit.fluxcd.io/prune: disabled`), the volsync cache PVC, the
  OpenBao path `infra/kubernetes/main/volsync/node-red-data`, and the restic
  repository in MinIO.
- Deleted with the component: the Backstage entity and the `office` / `basement`
  flow docs. Those pages described Node-RED implementations; keeping them would
  document flows that no longer exist.

## Consequences

- Positive: one automation runtime fewer, one public route fewer, one volsync
  repository and PVC fewer.
- Positive: an idle, semi-broken deployment no longer shows up in dashboards as
  a working component.
- Negative: Node-RED's visual flow debugging is gone. Anything that still needs
  a flow-shaped graph has to be expressed in n8n.
- Negative: the `basement` and `office` automation behaviour is no longer
  documented anywhere in this repository. Home Assistant owns the logic now.

## More Information

- Live evidence gathered 2026-11-13: pod `node-red-78b8d7b89c-zkm4r`, creation
  2026-10-31T00:47Z, 0 restarts, log lines limited to
  `[server: Home Assistant] Connecting to http://home-assistant.home-automation.svc.cluster.local`
  every 5s; last volsync snapshot 2026-11-13T19:01Z.
- Removed paths: `kubernetes/main/apps/home-automation/node-red/`,
  `docs/backstage/components/node-red/`.
