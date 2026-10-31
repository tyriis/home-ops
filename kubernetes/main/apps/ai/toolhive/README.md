# toolhive

The ToolHive operator (OSS/community edition) runs in the cluster's `ai` namespace alongside the other
AI workloads. It is deployed from `oci://ghcr.io/stacklok/toolhive/toolhive-operator` at version
0.56.0, together with its companion CRDs chart `toolhive-operator-crds` in the same namespace. This is
the cluster's MCP (Model Context Protocol) platform: MCP servers for agents are declared as ToolHive
CRs and reconciled by this operator.

## Layout

```text
kubernetes/main/apps/ai/
├── namespace.yaml                # the ai Namespace, prune-disabled (owned by the parent ai app dir)
└── toolhive/
    ├── README.md
    ├── flux-sync.yaml            # Flux Kustomization that reconciles ./app
    └── app/
        ├── kustomization.yaml          # lists the five manifests below
        ├── oci-repository-crds.yaml    # OCIRepository for the toolhive-operator-crds chart (0.56.0)
        ├── helm-release-crds.yaml      # HelmRelease installing the CRDs, no values overrides
        ├── oci-repository.yaml         # OCIRepository for the toolhive-operator chart (0.56.0)
        ├── helm-release.yaml           # operator HelmRelease: rbac scope, resources, dependsOn CRDs
        └── rbac-events.yaml            # Role + RoleBinding: core v1 events for the operator SA
```

## Notes

- This install lives in the existing `ai` namespace rather than a dedicated `mcp-system` namespace,
  because it is AI platform infrastructure. The namespace is created by
  `kubernetes/main/apps/ai/namespace.yaml` (from `app/`: `../../namespace.yaml`), so this app has no
  namespace file of its own.
- The CRDs come from the separate `toolhive-operator-crds` chart. Upstream ships them under
  `templates/` (not `crds/`), so they are templated and upgrade in place, and they carry the
  `helm.sh/resource-policy: keep` annotation — uninstalling the release leaves them behind.
- The operator HelmRelease uses `dependsOn` on the `toolhive-operator-crds` release so Helm installs
  the CRDs first.
- CRDs and operator must stay in the same namespace: Helm stamps managed CRDs with
  `meta.helm.sh/release-namespace`, so moving one without the other breaks adoption.
- The operator runs namespace-scoped: `rbac.scope: namespace` with `allowedNamespaces: [ai]`. The chart
  then emits a `RoleBinding` in `ai` instead of a `ClusterRoleBinding` and sets `WATCH_NAMESPACE=ai` on
  the manager, so it stops watching secrets cluster-wide. The `ClusterRole` object is still rendered
  (it holds the rules) but grants nothing without a binding. Because upstream rejects the
  combination, `features.storageVersionMigrator` is set to `false` — that controller requires
  cluster scope.
- An extra `Role`/`RoleBinding` pair (`rbac-events.yaml`) grants the operator core `v1` `events`
  create/patch in `ai`. The chart only grants `events.k8s.io/events`, so the manager logs
  `events is forbidden` at startup and its events never show in `kubectl describe`. Drop these two
  objects once upstream grants the core group.
- 14 CRDs are installed: MCPServer, MCPGroup, MCPRegistry, MCPRemoteProxy, VirtualMCPServer,
  VirtualMCPCompositeToolDefinition, MCPOIDCConfig, MCPAuthzConfig, MCPExternalAuthConfig,
  MCPToolConfig, MCPTelemetryConfig, MCPWebhookConfig, MCPServerEntry, EmbeddingServer.
  MCPWebhookConfig serves `v1alpha1` only; every other CRD serves `v1beta1` (storage) plus the
  deprecated `v1alpha1`.

## Adding the first MCP server

Remote MCPs are not declared here: they are delivered by the sibling [`mcp-context7`](../mcp-context7)
and [`mcp-gh-grep`](../mcp-gh-grep) apps, which hold the `MCPRemoteProxy` CRs (context7 and grep.app)
with their Envoy HTTPRoutes and API-key policies. Local container-based `MCPServer` CRs stay out of
scope, as do `MCPRegistry`, `VirtualMCPServer`, OIDC and authz configuration. When that work starts,
note that the operator is namespace-scoped to `ai`: an MCP server CR placed in any other namespace is
not reconciled until that namespace is added to `operator.rbac.allowedNamespaces`. Follow the
upstream Kubernetes operator docs at <https://docs.stacklok.com/toolhive> and inspect the CRDs
actually installed on the cluster with:

```sh
kubectl get crd | grep toolhive.stacklok.dev
```

Prefer the `v1beta1` API version for custom resources; MCPWebhookConfig is the only CRD with no
`v1beta1`.
