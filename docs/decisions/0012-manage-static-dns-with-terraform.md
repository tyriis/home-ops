---
status: accepted
date: 2026-09-13
decision-makers: [tyriis]
---

# Manage static DNS records with Terraform instead of DNS CRDs

## Context and Problem Statement

Static DNS records — the Envoy Gateway aliases (`main-gateway`, `utility-gateway`), `nas`,
`mqtt`/`mqtt.lan`/`mqtt.home`, `minecraft`, and the public Cloudflare tunnel CNAMEs — were
managed inside the cluster as `external-dns` `DNSEndpoint` CRDs (`external-dns/unifi-records` and
`external-dns/cloudflare-records`), reconciled by Flux and applied by the external-dns `crd`
source.

On **2026-09-13** the external-dns chart was upgraded `1.21.1 → 1.22.0` (app `v0.22.0`). In
v0.22.0 the `crd` source was rewritten onto a controller-runtime cache and now builds its
`Namespaces` map as:

```go
// source/crd.go (v0.22.0) — buildCacheOptions
nsMap := map[string]crcache.Config{ namespace: {} }   // namespace == "" when --namespace is unset
byObject := crcache.ByObject{ Namespaces: nsMap, /* ... */ }
```

controller-runtime interprets an empty-string namespace key as a **literal namespace**, not
"all namespaces". With `--namespace` unset (our case) the informer cache therefore watches no
namespace, the `crd` source emits **zero endpoints**, and the failure is silent: the controller
logs "All records are already up to date" while the desired set no longer contains any
DNSEndpoint record.

The blast radius of that silence was the entire main cluster:

- `main-gateway.techtales.io` was the only DNSEndpoint record that carried an ownership TXT, so
  `policy: sync` **deleted** it. Every one of ~50 gateway-route CNAMEs points at it, so essentially
  all main-cluster hostnames stopped resolving (Home Assistant, media, Grafana, Rook, …).
- `external`, `nas`, `mqtt.lan` and `mqtt.home` were never (re)created.
- `nas-gateway`/`mqtt`/`minecraft` survived only because they are unowned records that happened to
  exist in the Unifi controller already.

The obvious in-place workaround is not usable: setting `--namespace=networking` fixes the `crd`
cache but the flag is **global**, so it simultaneously stops the `gateway-httproute` source from
watching the many namespaces that actually own the HTTPRoutes.

The `crd` source is a shared upstream component we do not control; the records it was responsible
for are few, slow-changing, identity-like values (A/CNAME targets) — i.e. infrastructure state,
not cluster-derived state.

## Decision Drivers

- Core DNS must not depend on the internal cache/namespace behaviour of a single controller
  version.
- Static records are declarative infrastructure (fixed IPs / tunnel hostnames); they should be
  reviewable, plan-able and reconcilable independently of the cluster.
- Keep the automation that _does_ work: `gateway-httproute` correctly generates every application
  hostname from `HTTPRoute` resources and is unaffected by this bug.
- Reuse the existing Terraform estate: the private Unifi DNS repo (ADR `0002`) and the Cloudflare
  repo.
- Do not maintain a fork or pin an old external-dns in order to keep a fragile source alive.
- Minimise the number of DNS control planes and the number of places a record can vanish from.

## Considered Options

- **Terraform for static records** (Unifi + Cloudflare providers), keep `gateway-httproute` in-cluster
- Keep DNSEndpoints, pin external-dns back to `1.21.1` (and revert the GA-prefix annotations)
- Keep DNSEndpoints, work around with `--namespace=networking`
- Fork/patch external-dns (or wait for an upstream fix) and keep DNSEndpoints
- Keep the records hand-managed in the Unifi / Cloudflare UIs

## Decision Outcome

Chosen option: **Manage static DNS records with Terraform**, because it removes our dependence on
the broken `crd` source entirely, puts slow-changing infrastructure records under `plan`/review,
and keeps the working `gateway-httproute` automation for application hostnames.

Concrete parameters:

- Remove `- crd` from `sources` in the main `external-dns-unifi` and `external-dns-cloudflare`
  HelmReleases; `gateway-httproute` remains.
- Remove the `external-dns-{unifi,cloudflare}-records` Flux Kustomizations and the
  `unifi-records/` / `cloudflare-records/` `DNSEndpoint` directories.
- Static records move to Terraform:
  - **Unifi:** `main-gateway A 192.168.100.200`, `utility-gateway A 192.168.100.40`,
    `nas A 192.168.100.2`, `mqtt A 192.168.100.201`, `mqtt.lan`/`mqtt.home CNAME mqtt.techtales.io`,
    `minecraft A 192.168.100.202`.
  - **Cloudflare (proxied to the tunnel):** `main-gateway`, `utility-gateway`.
- `nas-gateway` and `external` are retired and are **not** carried over.
- Until the records are imported, they are hand-managed in the Unifi/Cloudflare UIs so no service
  is left without DNS.

### Consequences

- Good, because static DNS no longer depends on the external-dns `crd` source, whose v0.22.0 cache
  bug silently dropped every record.
- Good, because static records are reconciled by `terraform plan`/`apply` and survive (indeed are
  independent of) cluster outages — a cluster-wide DNS failure can no longer delete an alias record.
- Good, because the `gateway-httproute` automation keeps working and remains the single source of
  truth for application hostnames.
- Neutral, because DNS now has two control planes: Terraform for static records, in-cluster
  external-dns for `HTTPRoute`-derived records. Ownership is explicit by record class.
- Neutral, because the records now live outside this repo (Unifi/Cloudflare Terraform repos),
  which adds a small cross-repo hop for changes.
- Bad, because Terraform state and provider credentials must be managed and kept secure for both
  the Unifi and Cloudflare providers.
- Bad, because there is a migration gap: until the records are codified, they are hand-managed with
  no drift detection.
- Bad, because the upstream `crd` source may become useful again for dynamic records; the decision
  removes an option rather than fixing the component.

### Confirmation

- `kubectl get dnsendpoint -A` shows no externally-managed static records, and neither external-dns
  instance lists `crd` in `sources`.
- `gateway-httproute` continues to generate the application endpoints (visible as
  `Endpoints generated from HTTPRoute …` and as resolving CNAMEs to `main-gateway`).
- `terraform plan` in the Unifi and Cloudflare repos reports the static records with no drift.
- `getent hosts hass.techtales.io` (and the DNS verification script) resolves the full deployed set;
  the 2026-09-13 outage set is fully green.

## Pros and Cons of the Options

### Terraform for static records (chosen)

- Good, because it is independent of controller-version bugs and of cluster availability.
- Good, because changes are reviewed via `plan` before they touch DNS.
- Neutral, because it splits DNS ownership between two systems (by record class).
- Bad, because it introduces state + credentials management and a hand-managed gap until migration.

### Pin external-dns back to `1.21.1`

- Good, because DNSEndpoints would work again with no migration.
- Bad, because the GA annotation-prefix migration (`external-dns.kubernetes.io/…`) would have to be
  reverted, re-introducing the deprecated `alpha` prefix.
- Bad, because it holds external-dns on an old version and leaves the `crd` bug for later; the same
  class of silent, destructive failure stays possible.

### Workaround `--namespace=networking`

- Good, because it fixes the `crd` cache with one flag and no code change.
- Bad, because the flag is global: `gateway-httproute` would stop watching HTTPRoutes outside
  `networking`, breaking the (currently correct) application hostnames. Not viable.

### Fork/patch external-dns and keep DNSEndpoints

- Good, because it keeps the CRD workflow and fixes the root cause.
- Bad, because it adds a maintained fork/build pipeline (or waiting on upstream) for a component
  whose records are static and low-volume. Disproportionate cost.

### Hand-managed records in the UIs

- Good, because it is immediate and requires no new infrastructure.
- Bad, because there is no review, no drift detection, no history, and it is easy to lose a record
  exactly as the alias record was lost during the incident. Suitable only as the interim state.

## More Information

- external-dns v0.22.0 release notes: <https://github.com/kubernetes-sigs/external-dns/releases/tag/v0.22.0>
- `source/crd.go` `buildCacheOptions` (controller-runtime cache migration, PR #6312 family)
- Related ADR: `0002-make-terraform-unifi-repo-private.md` (existing Unifi Terraform estate)
- Incident: 2026-09-13 — external-dns `1.21.1 → 1.22.0`, `main-gateway` deleted, main-cluster DNS
  outage; root-caused to the `crd` cache namespace scoping.
