# OpenTelemetry Observability Stack Design

**Date:** 2026-08-12
**Issues:** [#3851](https://github.com/tyriis/home-ops/issues/3851), [#7395](https://github.com/tyriis/home-ops/issues/7395), [#9987](https://github.com/tyriis/home-ops/issues/9987)
**Scope:** opentelemetry, tempo

## Overview

Deploy an OpenTelemetry-native observability foundation to the main cluster in **Phase 1**, running *alongside* the existing stack. This phase delivers the OTel Operator + Collector with OTLP ingress for external sources (local opencode, node_exporter) — handling traces, metrics, and logs — and Tempo as the tracing backend. Promtail and Prometheus ServiceMonitors stay in place; Loki receives an additive `otlp_config` for OTLP log ingestion.

## Phasing

This spec covers **Phase 1 only**. The full Promtail → OTel migration is intentionally deferred so the existing stack keeps working untouched.

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** | OTel Operator + Collector (OTLP ingress for traces/metrics/logs), Tempo, external sources (opencode, node_exporter) | This spec |
| Phase 2 | filelog receiver replaces Promtail, utility-cluster collector forwards logs to main | Future |
| Phase 3 | Auto-instrumentation of in-cluster apps via the operator | Future |

## Architecture

```
┌─ local opencode ─────┐    ┌─ local node_exporter ─┐
└──────────┬───────────┘    └───────────┬────────────┘
           │ OTLP HTTP (HTTPRoute/Envoy + bearer token)
           ▼
┌──────────────────────────────────────────────────────────┐
│  MAIN CLUSTER - observability namespace                   │
│                                                           │
│  ┌──────────────────────────────────────────────────┐    │
│  │ OTel Collector (DaemonSet, 1 per node)            │    │
│  │                                                    │    │
│  │ Receivers:                                         │    │
│  │   otlp (gRPC :4317, HTTP :4318)                    │    │
│  │                                                    │    │
│  │ Processors: batch, memory_limiter                   │    │
│  │                                                    │    │
│  │ Exporters:                                         │    │
│  │   prometheusremotewrite →  Prometheus (existing)    │    │
│  │   otlphttp/loki          →  Loki /otlp/v1/logs     │    │
│  │   otlp/tempo             →  Tempo (new)            │    │
│  └──────────────────────────────────────────────────┘    │
│                                                           │
│  Prometheus (unchanged)    Loki 3.x (OTLP logs)           │
│  ServiceMonitors stay       Promtail still ships logs     │
│                                                           │
│  Tempo (new)                Promtail (unchanged)          │
│  SingleBinary, S3-backed      Remains in place            │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  UTILITY CLUSTER (Phase 2 - future)                       │
│  ┌──────────────────────────────────────────────────┐    │
│  │ OTel Collector (DaemonSet, minimal)               │    │
│  │   filelog → forward via OTLP to main cluster       │    │
│  │   host metrics → utility Prometheus (kept)         │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| OTel management | `opentelemetry-operator` (CRD-based) | 7 kubesearch repos vs 3 for standalone; auto-instrumentation for future app migration |
| Log collection | Promtail (unchanged) in Phase 1 | filelog receiver deferred to Phase 2; existing Promtail keeps shipping pod logs untouched |
| Collector mode | DaemonSet (all-in-one) | Rolled out as DaemonSet from Phase 1 to avoid a mode change; `/var/log/pods` access needed in Phase 2; homelab scale sufficient |
| Tracing backend | Tempo (SingleBinary, S3-backed) | Purpose-built for traces; Loki 3.x trace support is basic only |
| Loki log ingestion | OTLP `/otlp/v1/logs` | External sources (opencode) send logs via OTLP; native in Loki 3.7.6; Promtail continues on legacy push API in parallel |
| Prometheus metrics | prometheusremotewrite exporter | Existing Prometheus unchanged; no experimental otlp-write-receiver feature gate needed |
| External access | HTTPRoute via Envoy Gateway + bearer token | Matches existing observability URL pattern; token from OpenBao |
| Utility cluster Prometheus | Keep both during transition | OTel Collector forwards to main; existing kube-prometheus-stack stays for now |

## Configuration

### opentelemetry-operator

- **Chart:** `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-operator`
- **Version:** v0.120.x (operator collector image 0.158.x)
- **Namespace:** `observability`
- **Replicas:** 1
- **cert-manager:** `admissionWebhooks.certManager.enabled: true` (operator creates its own Issuer+Certificate)
- **DependsOn:** `cert-manager`

### OpenTelemetryCollector (DaemonSet CR)

- **API:** `opentelemetry.io/v1beta1`
- **Mode:** `daemonset` — rolled out as DaemonSet from Phase 1 to avoid a mode change in Phase 2 (filelog needs `/var/log/pods`)
- **Image:** `otel/opentelemetry-collector-contrib`
- **Receivers:**
  - `otlp` - gRPC `0.0.0.0:4317`, HTTP `0.0.0.0:4318` (bearer token auth on both)
- **Processors:** `batch`, `memory_limiter`
- **Exporters:**
  - `prometheusremotewrite` → `http://kube-prometheus-stack-prometheus.observability.svc:9090/api/v1/write`
  - `otlphttp/loki` → `http://loki-headless.observability.svc.cluster.local:3100/otlp`
  - `otlp/tempo` → `http://tempo.observability.svc.cluster.local:4317`
- **Extensions:** `health_check`, `bearertokenauth` (token from ExternalSecret/OpenBao)
- **HTTPRoute (native CRD):** `otel.techtales.io` via envoy gateway, TLS, bearer token auth
- **Resources:** 100m CPU / 256Mi memory requests, 1Gi memory limit

### Tempo

- **Chart:** `oci://ghcr.io/grafana/helm-charts/tempo` (monolithic, not tempo-distributed)
- **Version:** v1.24.x
- **Mode:** SingleBinary
- **Retention:** 168h (7 days) - standard for homelab traces
- **Storage:** S3 (same MinIO as Loki), new `tempo` bucket, scoped credentials via ExternalSecret
- **Receivers:** OTLP gRPC `0.0.0.0:4317`, HTTP `0.0.0.0:4318`
- **MetricsGenerator:** enabled, remote_write to Prometheus for span metrics and service graphs
- **Report:** telemetry disabled (`reportingEnabled: false`)
- **Resources:** 100m/256Mi requests, 2Gi memory limit
- **Security:** `readOnlyRootFilesystem: true`, capabilities `drop: [ALL]`, `seccomp: RuntimeDefault`
- **ServiceMonitor:** enabled

### Loki (modified — additive)

- **Change:** Add `limits_config.otlp_config` block (~15 lines) to map OTLP resource attributes to Loki labels for external OTLP logs (opencode). Promtail continues on the existing push API in parallel.
- **Attributes indexed:** `service.name`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`
- **Endpoint:** `/otlp/v1/logs` already enabled by default in Loki 3.7.6 (SingleBinary mode)
- **No other Loki config changes needed**

### Security

| Path | Method | Implementation |
|---|---|---|
| External → main cluster OTLP | HTTPRoute (TLS) + bearer token | `bearertokenauth` extension on otlp receiver; token from OpenBao via ExternalSecret |
| Utility → main cluster (Phase 2) | mTLS | cert-manager certificates on both sides |
| In-cluster apps → collector | No auth | Internal service access (`otel-collector.observability.svc`) |

## File Changes

### New Files

**`opentelemetry/` (9 files):**
```
kubernetes/main/apps/observability/opentelemetry/
├── flux-sync.yaml           # 3 Kustomizations: operator, collector, observability
├── operator/
│   ├── kustomization.yaml   # resources: oci-repository.yaml, helm-release.yaml
│   ├── helm-release.yaml    # opentelemetry-operator chart
│   └── oci-repository.yaml  # OCI chart source
├── collector/
│   ├── kustomization.yaml   # resources: collector.yaml, external-secret.yaml
│   ├── collector.yaml       # OpenTelemetryCollector CR (DaemonSet)
│   └── external-secret.yaml # Bearer token (OpenBao → Secret)
└── observability/
    ├── kustomization.yaml   # resources: service-monitor.yaml
    └── service-monitor.yaml # Collector self-monitoring (port 8888)
```

**`tempo/` (7 files):**
```
kubernetes/main/apps/observability/tempo/
├── flux-sync.yaml           # 2 Kustomizations: app, observability
├── app/
│   ├── kustomization.yaml   # resources: oci-repository.yaml, helm-release.yaml, external-secret.yaml
│   ├── helm-release.yaml    # Tempo chart (SingleBinary, S3-backed)
│   ├── oci-repository.yaml  # OCI chart source
│   └── external-secret.yaml # tempo-s3-scoped (OpenBao → Secret)
└── observability/
    ├── kustomization.yaml   # resources: service-monitor.yaml
    └── service-monitor.yaml # Tempo self-monitoring
```

### Modified Files

| File | Change |
|---|---|
| `kubernetes/main/apps/observability/kustomization.yaml` | Add `./opentelemetry/flux-sync.yaml` and `./tempo/flux-sync.yaml` to resources |
| `grafana/instance/datasource.yaml` | Add Tempo `GrafanaDatasource` (type: tempo, URL: `http://tempo.observability.svc:3200`) |
| `loki/app/helm-release.yaml` | Add `limits_config.otlp_config` resource attribute mapping |

### Removed

No files are removed in Phase 1. The Promtail directory and its parent references remain in place.

### Flux Dependency Chain

```
cert-manager
  └── opentelemetry-operator
        ├── opentelemetry-collector (also dependsOn external-secrets-stores)
        └── opentelemetry-observability

external-secrets-stores
  ├── opentelemetry-collector
  └── tempo

opentelemetry-operator
  ├── opentelemetry-collector
  └── opentelemetry-observability

kube-prometheus-stack
  └── tempo-observability (ServiceMonitor)
```

## What's NOT Changing

- **Promtail:** Remains deployed and continues shipping pod logs to Loki (filelog migration deferred to Phase 2)
- **Prometheus:** All ~40 existing ServiceMonitors/PodMonitors/ScrapeConfigs continue unchanged
- **Loki:** Storage, schema, retention, S3 backend all unchanged; only additive `otlp_config` added for OTLP logs
- **Grafana:** All dashboards, datasources (Prometheus, Alertmanager, Loki) preserved; Tempo added
- **Alertmanager:** Unchanged
- **kube-prometheus-stack:** No version bump, no HelmRelease changes
- **All other observability apps:** Untouched

## Post-Deployment Verification

1. OTel Collector DaemonSet pods running on all nodes
2. External OTLP reachable at `https://otel.techtales.io` — verify with `curl -H "Authorization: Bearer <token>"` 
3. Tempo receiving traces — verify Tempo datasource in Grafana Explore
4. Tempo MetricsGenerator producing span metrics in Prometheus
5. External metrics (node_exporter) visible in Prometheus via remote_write
6. External logs (opencode) reach Loki `/otlp/v1/logs` — verify in Grafana Explore with otlp_config labels
7. Promtail still shipping logs — verify recent log lines in Grafana Explore
8. All existing ServiceMonitors still functional — verify Prometheus targets and Grafana dashboards

## References

- https://github.com/open-telemetry/opentelemetry-operator
- https://opentelemetry.io/docs/kubernetes/helm/operator/
- https://github.com/grafana/tempo
- https://grafana.com/docs/loki/latest/send-data/otel/
- https://kubesearch.dev/hr/ghcr.io-open-telemetry-opentelemetry-helm-charts-opentelemetry-operator
- https://github.com/tyriis/home-ops/issues/3851
- https://github.com/tyriis/home-ops/issues/7395
- https://github.com/tyriis/home-ops/issues/9987
