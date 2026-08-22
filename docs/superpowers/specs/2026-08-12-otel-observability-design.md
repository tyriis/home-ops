# OpenTelemetry Observability Stack Design

**Date:** 2026-08-12
**Issues:** [#3851](https://github.com/tyriis/home-ops/issues/3851), [#7395](https://github.com/tyriis/home-ops/issues/7395), [#9987](https://github.com/tyriis/home-ops/issues/9987)
**Scope:** opentelemetry, tempo

## Overview

Deploy an OpenTelemetry-native observability foundation to the main cluster in **Phase 1**, running *alongside* the existing stack. This phase delivers the OTel Operator + Collector with bearer-token OTLP ingress for local opencode telemetry (traces, logs, and metrics), and Tempo as the tracing backend. Metrics — the primary opencode signal — flow natively via OTLP to Prometheus. Promtail stays untouched; Prometheus and Loki receive additive config (`enableOTLPReceiver` and `otlp_config` respectively).

## Phasing

This spec covers **Phase 1 only**. The full Promtail → OTel migration is intentionally deferred so the existing stack keeps working untouched.

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1** | OTel Operator + Collector (OTLP ingress for traces/logs/metrics), Tempo, local opencode | This spec |
| Phase 2 | filelog receiver replaces Promtail, utility-cluster collector | Future |
| Phase 3 | Auto-instrumentation of in-cluster apps via the operator | Future |

## Architecture

```
┌─ local opencode ─────┐
└──────────┬───────────┘
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
│  │   otlphttp/prom          →  Prometheus /api/v1/otlp│    │
│  │   otlphttp/loki          →  Loki /otlp/v1/logs     │    │
│  │   otlp/tempo             →  Tempo (new)            │    │
│  └──────────────────────────────────────────────────┘    │
│                                                           │
│  Prometheus (OTLP recv)    Loki 3.x (OTLP logs)           │
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
| Metrics ingestion | `otlphttp` → Prometheus native OTLP receiver | Native OTLP end-to-end (no remote-write conversion); `enableOTLPReceiver: true`; single-endpoint write accepted — 3-replica scatter revisited with VictoriaMetrics migration |
| External access | HTTPRoute via Envoy Gateway + bearer token | Matches existing observability URL pattern; token from OpenBao; single consumer (opencode) in Phase 1 |
| Utility cluster Prometheus | Keep both during transition | OTel Collector forwards to main; existing kube-prometheus-stack stays for now |

## Configuration

### opentelemetry-operator

- **Chart:** `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts/opentelemetry-operator`
- **Version:** v0.120.x (operator collector image 0.158.x) — pin exact `ref.tag` at implementation time (repo convention, no `x` wildcards)
- **Namespace:** `observability`
- **Replicas:** 1
- **cert-manager:** `admissionWebhooks.certManager.enabled: true` (operator creates its own Issuer+Certificate)
- **DependsOn:** `cert-manager`

### OpenTelemetryCollector (DaemonSet CR)

- **API:** `opentelemetry.io/v1beta1`
- **Mode:** `daemonset` — rolled out as DaemonSet from Phase 1 to avoid a mode change in Phase 2 (filelog needs `/var/log/pods`)
- **Image:** `otel/opentelemetry-collector-contrib` — set explicitly; the operator defaults to the distro image, which lacks the `bearertokenauth` extension (contrib-only)
- **Receivers:**
  - `otlp` - gRPC `0.0.0.0:4317`, HTTP `0.0.0.0:4318` (bearer token auth on both)
- **Processors:** `batch`, `memory_limiter`
- **Exporters:**
  - `otlphttp/prom` → `http://kube-prometheus-stack-prometheus.observability.svc:9090/api/v1/otlp` (native OTLP; exporter appends `/v1/metrics`)
  - `otlphttp/loki` → `http://loki-headless.observability.svc.cluster.local:3100/otlp`
  - `otlp/tempo` → `http://tempo.observability.svc.cluster.local:4317`
  - `prometheus` → `0.0.0.0:8888` (self-monitoring, scraped by ServiceMonitor)
- **Scatter note:** single-endpoint write; the 3-replica Prometheus (no Thanos) scatters OTLP data across replicas. Accepted as a temporary limitation — resolved by the planned VictoriaMetrics migration.
- **Extensions:** `health_check`, `bearertokenauth` (token from ExternalSecret/OpenBao)
- **Service wiring:** list `bearertokenauth` under `service.extensions`; use separate pipelines for traces/metrics/logs; in-cluster `otlphttp` exporters use `tls.insecure: true`
- **Auth token injection:** `spec.env[].valueFrom.secretKeyRef` → OpenBao-backed Secret; referenced as `${env:OTEL_BEARER_TOKEN}` in `bearertokenauth` (escape as `$${env:...}` if Flux postBuild substitutions are used)
- **HTTPRoute (native CRD):** `otel.techtales.io` via envoy gateway, TLS, bearer token auth (annotate `gatus.home-operations.com/endpoint` per repo convention)
- **Resources:** 100m CPU / 256Mi memory requests, 1Gi memory limit
- **Security:** `readOnlyRootFilesystem: true`, capabilities `drop: [ALL]`, `seccomp: RuntimeDefault`
- **Tolerations:** none in Phase 1; add control-plane tolerations in Phase 2 for filelog coverage

### Tempo

- **Chart:** `oci://ghcr.io/grafana/helm-charts/tempo` (monolithic, not tempo-distributed)
- **Version:** v1.24.x — pin exact `ref.tag` at implementation time (repo convention)
- **Mode:** SingleBinary
- **Retention:** 168h (7 days) - standard for homelab traces
- **Storage:** S3 (same MinIO as Loki), new `tempo` bucket, scoped credentials via ExternalSecret. The `tempo` bucket + credentials must be provisioned before rollout (Terraform `terraform-minio` or manual, mirroring the existing `loki` S3 bucket)
- **Receivers:** OTLP gRPC `0.0.0.0:4317`, HTTP `0.0.0.0:4318`
- **MetricsGenerator:** disabled in Phase 1 — span metrics/service graphs deferred; avoids enabling the Prometheus remote-write receiver (see "What's NOT Changing")
- **Report:** telemetry disabled (`reportingEnabled: false`)
- **Resources:** 100m/256Mi requests, 2Gi memory limit
- **Security:** `readOnlyRootFilesystem: true`, capabilities `drop: [ALL]`, `seccomp: RuntimeDefault`
- **ServiceMonitor:** hand-rolled via `observability/service-monitor.yaml` (Tempo self-monitoring)

### Loki (modified — additive)

- **Change:** Add `limits_config.otlp_config` block (~15 lines) to map OTLP resource attributes to Loki labels for external OTLP logs (opencode). Promtail continues on the existing push API in parallel.
- **Attributes indexed:** `service.name`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name` (external opencode logs carry only `service.name`; `k8s.*` labels become meaningful in Phase 2 with filelog)
- **`ignore_defaults: true`:** set in `otlp_config` so only the four attributes above are indexed (Loki otherwise adds 17 default resource-attribute labels)
- **Endpoint:** `/otlp/v1/logs` already enabled by default in Loki 3.7.6 (SingleBinary mode)
- **No other Loki config changes needed**

### kube-prometheus-stack (modified — additive)

- **Change:** `prometheus.prometheusSpec.enableOTLPReceiver: true` (maps to Prometheus `--web.enable-otlp-receiver`, GA since Prometheus 3.0)
- **Endpoint:** native OTLP at `/api/v1/otlp/v1/metrics` (HTTP only); the collector's `otlphttp/prom` exporter targets `/api/v1/otlp`
- **No other kube-prometheus-stack changes** — no version bump, ServiceMonitors untouched
- **Note:** Prometheus runs 3 replicas without Thanos; a single-endpoint OTLP write scatters data across replicas. Accepted temporarily; resolved by the planned VictoriaMetrics migration.

### Security

| Path | Method | Implementation |
|---|---|---|
| External (opencode) → main cluster OTLP | HTTPRoute (TLS) + bearer token | `bearertokenauth` extension on otlp receiver; token from OpenBao via ExternalSecret |
| Utility → main cluster (Phase 2) | mTLS | cert-manager certificates on both sides |
| In-cluster apps → collector | Deferred (no in-cluster senders in Phase 1) | Revisited in Phase 3 with auto-instrumentation |

## File Changes

### New Files

**`opentelemetry/` (10 files):**
```
kubernetes/main/apps/observability/opentelemetry/
├── flux-sync.yaml           # 3 Kustomizations: operator, collector, observability
├── operator/
│   ├── kustomization.yaml   # resources: oci-repository.yaml, helm-release.yaml
│   ├── helm-release.yaml    # opentelemetry-operator chart
│   └── oci-repository.yaml  # OCI chart source
├── collector/
│   ├── kustomization.yaml   # resources: collector.yaml, external-secret.yaml, http-route.yaml
│   ├── collector.yaml       # OpenTelemetryCollector CR (DaemonSet)
│   ├── external-secret.yaml # Bearer token (OpenBao → Secret)
│   └── http-route.yaml      # HTTPRoute otel.techtales.io → collector OTLP service
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
| `grafana/instance/datasource.yaml` | Add Tempo `GrafanaDatasource` (type: tempo, URL: `http://tempo.observability.svc:3200`); consider `tracesToLogsV2`/`traceToMetrics` linking to existing Loki/Prometheus |
| `loki/app/helm-release.yaml` | Add `limits_config.otlp_config` resource attribute mapping |
| `kube-prometheus-stack/app/helm-release.yaml` | Add `prometheusSpec.enableOTLPReceiver: true` |

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
  ├── opentelemetry-observability (ServiceMonitor CRD)
  └── tempo-observability (ServiceMonitor)
```

> **Note:** `external-secrets-stores` lives in the `secops` namespace (not `observability`). `opentelemetry-observability` and `tempo-observability` both depend on `kube-prometheus-stack` for the ServiceMonitor CRD; `tempo-observability` also depends on the `tempo` app Kustomization.

## What's NOT Changing

- **Promtail:** Remains deployed and continues shipping pod logs to Loki (filelog migration deferred to Phase 2)
- **Prometheus:** Only additive `enableOTLPReceiver: true` (native OTLP receiver); all ~40 ServiceMonitors/PodMonitors/ScrapeConfigs continue as-is — no other config changes
- **Loki:** Storage, schema, retention, S3 backend all unchanged; only additive `otlp_config` added for OTLP logs
- **Grafana:** All dashboards, datasources (Prometheus, Alertmanager, Loki) preserved; Tempo added
- **Alertmanager:** Unchanged
- **kube-prometheus-stack:** No version bump; single additive HelmRelease change (`enableOTLPReceiver`)
- **All other observability apps:** Untouched

## Post-Deployment Verification

1. OTel Collector DaemonSet pods running on all nodes
2. External OTLP reachable at `https://otel.techtales.io` — verify with `curl -H "Authorization: Bearer <token>"` 
3. Tempo receiving traces — verify Tempo datasource in Grafana Explore
4. External logs (opencode) reach Loki `/otlp/v1/logs` — verify in Grafana Explore with otlp_config labels
5. External metrics (opencode) reach Prometheus via native OTLP — verify `service.name`-labelled series in Grafana Explore (appear intermittently across replicas due to accepted scatter; retry, not a bug)
6. Collector self-monitoring — verify `otel-collector` target in Prometheus (port 8888)
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
