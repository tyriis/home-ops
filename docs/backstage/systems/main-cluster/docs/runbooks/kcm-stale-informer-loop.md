# KCM Stale Informer Loop

## Overview

`kube-controller-manager` (KCM) loops forever on:

```text
E1102 18:47:57.896793 1 reflector.go:227] "Failed to watch" err="failed to list
*v1.PartialObjectMetadata: the server could not find the requested resource"
logger="UnhandledError" reflector=".../metadatainformer/informer.go:146"
```

The garbage collector keeps a metadata informer per resource type it has seen.
When a CRD is deleted (typically an operator offboard), the informer for that
resource keeps watching a now-removed GVR. A 404 never invalidates a stale
reflector, so it retries forever. Only a KCM process restart clears it: the
fresh process reads discovery at startup and never recreates the informer.

The loop runs on the KCM **leader only** — the other two replicas are clean by
definition.

**Owner:** Platform / SRE Team

## Alert Severity and Impact

| Attribute | Value                                                                                                                                             |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Alert     | `KCMStaleInformerLoop` (vmalert, VictoriaLogs, evaluated from utility)                                                                            |
| Severity  | warning                                                                                                                                           |
| Pages     | no                                                                                                                                                |
| Impact    | Log growth (~7 lines/min) and ~2 wasted 404s/min against the API server. Cosmetic. The GC itself is unaffected — verify below before remediating. |

## Detection

Confirm the loop and its rate on each control-plane node:

```sh
for p in talos01 talos02 talos03; do
  printf '%s ' "$p"
  kubectl --context readonly@main -n kube-system logs \
    "kube-controller-manager-$p" --since=24h | grep -c "Failed to watch"
done
```

One node with a large count, the others at 0, is the signature.

## Pre-check — rule out real GC damage

The loop is cosmetic only if the GC is still working. Check for objects stuck
in termination (expect zero; a growing set means a different problem):

```sh
kubectl --context readonly@main get pods -A -o json \
  | jq -r '.items[] | select(.metadata.deletionTimestamp) | .metadata.namespace + "/" + .metadata.name'
```

## Remediation

Delete the affected pod. Talos regenerates it automatically; expect a few
seconds of KCM downtime on that node (leader election re-homes).

```sh
kubectl --context admin@main -n kube-system delete pod kube-controller-manager-talosNN
```

Replace `NN` with the flagged node. Delete only the one affected pod.

## Verification

All three pods must read 0 going forward:

```sh
for p in talos01 talos02 talos03; do
  printf '%s ' "$p"
  kubectl --context readonly@main -n kube-system logs \
    "kube-controller-manager-$p" --since=5m | grep -c "Failed to watch"
done
```

The new leader may be a different node — a fresh process cannot have the stale
informer, so any placement is fine.

## Notes

- Recurs on every offboard that removes CRDs; first seen 2026-11-02, onset to
  the second after the `cnpg-system/dbman` Flux garbage collection deleted the
  dbman operator's release.
- No functional data path is involved; this can wait for a convenient window.
- The trigger condition is structural upstream behaviour — a permanent fix
  belongs in client-go informer invalidation on 404, not in this cluster.
