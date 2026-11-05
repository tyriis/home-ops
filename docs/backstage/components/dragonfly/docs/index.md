# Dragonfly

Dragonfly is the in-memory datastore (Redis-compatible) that backs several services on the main cluster. The operator manages each instance through a `Dragonfly` CR (`dragonflydb.io/v1alpha1`).

## Deployment

All instances come from one template, `kubernetes/components/dragonfly/cluster.yaml`. The shared cluster instance has its own CR in `kubernetes/main/apps/dragonfly-system/dragonfly/cluster/crd/cluster.yaml`.

| Instance                    | Namespace        | Consumer                       |
| --------------------------- | ---------------- | ------------------------------ |
| `dragonfly`                 | dragonfly-system | shared cluster cache           |
| `firecrawl-dragonfly`       | firecrawl-system | firecrawl queue and rate limit |
| `locking-service-dragonfly` | home-automation  | locking-service lock table     |
| `n8n-dragonfly`             | home-automation  | n8n queue mode (BullMQ)        |
| `immich-dragonfly`          | media            | immich job queue and cache     |

All instances run `--cluster_mode=emulated` with 2 replicas.
No instance has a PVC.
All state is in-memory by design: a pod restart wipes the data, and a rollout therefore causes brief cache or queue churn.
The locking-service lock table re-registers from clients over a few minutes after a wipe.

## License: DSAL since v2.1.0

Upstream changed the license with v2.1.0, from BUSL-1.1 to the **Dragonfly Source-Available License (DSAL)**.
We crossed that boundary with the v2.0.2 → v2.1.0 bump (PR [#11701](https://github.com/tyriis/home-ops/pull/11701)).
DSAL is not an open-source license.
The terms we operate under:

- **Usage limit:** DSAL caps free production use at 100 vCPUs, counted across all concurrently running instances. Beyond the limit requires a paid commercial license. DSAL places no limit on non-production use.
- **No standalone redistribution:** we may embed dragonfly in our own applications. We must not distribute, sell, or sublicense it as a standalone database or caching product.
- **Usage monitoring:** upstream reserves the right to measure deployed instances remotely. The license text exempts air-gapped deployments and outbound firewall filtering. Our egress posture is compliant as-is.

**Our position:** the main cluster is 3 nodes and well below 100 vCPUs. Use is personal and internal, with no redistribution. Every term of the free grant is met.

**Re-check triggers:** re-read `LICENSE.md` in the upstream repo at every major-version bump. Re-assess if the fleet grows toward the vCPU limit or any instance is ever exposed to third parties.

Sources:

- [LICENSE.md at the pinned tag](https://github.com/dragonflydb/dragonfly/blob/v2.1/LICENSE.md)
- [Upstream announcement](https://www.dragonflydb.io/blog/introducing-dragonfly-enterprise)
- [Merge-time decision record](https://github.com/tyriis/home-ops/pull/11701#issuecomment-6667283436)
