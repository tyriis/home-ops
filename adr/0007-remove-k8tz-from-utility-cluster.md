---
status: accepted
date: 2026-05-15
decision-makers: [tyriis, jazzlyn]
---

# Remove k8tz Controller from the Utility Cluster — set timezone via env vars

## Context and Problem Statement

The utility cluster is a single-node Talos cluster managed by tyriis and jazzlyn.
During a Talos upgrade procedure, all control plane components are restarted,
including the k8tz admission webhook pod. Because k8tz was deployed with a
`MutatingWebhookConfiguration` that intercepts **all** pod creation events, the
following deadlock occurred:

1. The Talos upgrade cycled the k8tz pod, making the admission webhook endpoint unreachable.
2. The `tuppr` controller (and other workloads) attempted to restart their pods as nodes came back online.
3. The Kubernetes API server called the k8tz mutating webhook for every new pod, but the webhook was down.
4. The webhook timeout/failure policy blocked pod creation entirely, preventing the k8tz pod itself (or any other pod) from starting.
5. The cluster entered a deadlock — no new pods could be scheduled, and manual intervention was required to recover.

This is a known failure mode for admission webhooks on single-node clusters during upgrades: the webhook cannot serve requests while its own pod is unavailable, but pods cannot start without the webhook.

## Decision Drivers

- The Talos upgrade procedure must complete without manual intervention.
- The cluster is single-node — there is no second replica to keep the webhook available during upgrades.
- Pod creation must not depend on a component that becomes unavailable during its own lifecycle.
- The utility cluster runs stateless controllers and batch jobs — timezone consistency is a convenience, not a security boundary.

## Considered Options

- **Option 1: Remove k8tz entirely** — Uninstall the k8tz controller and its `MutatingWebhookConfiguration`. Set the `TZ` environment variable directly in deployment manifests.
- **Option 2: Keep k8tz with `failurePolicy: Ignore`** — Change the webhook failure policy so that when the webhook is unreachable, pod creation proceeds without timezone injection.
- **Option 3: Keep k8tz with a second replica and anti-affinity** — Run two k8tz replicas with pod anti-affinity so at least one is always available during rolling updates.
- **Option 4: Keep k8tz and use `namespaceSelector` to exempt system namespaces** — Narrow the webhook scope to only the namespaces that actually need timezone injection.

## Decision Outcome

Chosen option: **Option 1: Remove k8tz entirely** and set timezone via environment variables in deployment manifests.

On a single-node cluster, no amount of webhook configuration tuning fully eliminates
the risk of deadlock during upgrades. `failurePolicy: Ignore` would prevent the
deadlock but silently skip timezone injection during upgrades — the same operational
impact without removing the attack surface. The utility cluster has a small, known
set of deployments; maintaining the `TZ` variable in each manifest is simpler, more
transparent, and eliminates an entire failure mode.

### Consequences

- _Good, because_ admission webhook deadlock during upgrades is eliminated entirely.
- _Good, because_ deployments become self-documenting — the timezone is visible in the manifest instead of injected by a hidden controller.
- _Good, because_ removing k8tz reduces resource usage on the resource-constrained single-node cluster.
- _Good, because_ one less `MutatingWebhookConfiguration` reduces the attack surface and troubleshooting complexity.
- _Bad, because_ every new deployment that needs a specific timezone must explicitly set the `TZ` environment variable — it is no longer automatic.
- _Bad, because_ existing running pods must be re-deployed after the `TZ` variable is added to their manifests.
- _Bad, because_ if a deployment is created without `TZ` and the default timezone (UTC) is wrong, the issue is caught at review time rather than being handled automatically.

## Pros and Cons of the Options

### Option 1: Remove k8tz entirely

- Good, because the deadlock failure mode is permanently eliminated.
- Good, because the cluster has fewer moving parts.
- Good, because explicit environment variables are easier to debug than mutations.
- Neutral, because each deployment manifest needs a `TZ: Europe/Vienna` entry added once.
- Bad, because teams must remember to set `TZ` in new deployments.

### Option 2: Keep k8tz with `failurePolicy: Ignore`

- Good, because the deadlock is prevented — pods start even when the webhook is down.
- Bad, because during upgrades, pods are created _without_ timezone injection silently, which could cause subtle timing bugs (cron jobs firing at wrong times, log timestamps in UTC, etc.).
- Bad, because the webhook is still a single point of failure in the admission path.
- Bad, because `failurePolicy: Ignore` masks the underlying reliability problem.

### Option 3: Keep k8tz with a second replica and anti-affinity

- Bad, because the cluster is single-node — pod anti-affinity cannot place replicas on different nodes. Both replicas would run on the same node and go down together during the upgrade.
- Bad, because running two replicas of a sidecar injector on a resource-constrained node adds unnecessary overhead.

### Option 4: Keep k8tz with `namespaceSelector` exemption

- Good, because system-critical namespaces (e.g., `kube-system`, the k8tz namespace itself) are excluded, reducing the chance of a cluster-wide deadlock.
- Neutral, because the deadlock still occurs if a workload in a non-exempt namespace triggers the webhook while the k8tz pod is cycling.
- Bad, because it adds configuration complexity and still leaves the webhook as a potential chokepoint during upgrades.

## More Information

- [k8tz GitHub](https://github.com/k8tz/k8tz) — Admission controller for timezone injection
- The `TZ` environment variable is a POSIX standard: the Go `time` package, Python `datetime`, Java `ZoneId`, cron, and all major runtimes respect it. Supported values are IANA time zone names (e.g., `Europe/Vienna`, `America/New_York`).
