# oidc

Kustomize component that adds [Google](https://accounts.google.com) OIDC authentication to an Envoy Gateway `HTTPRoute` via a `SecurityPolicy`.
Authentication is handled by a shared oauth2-proxy instance at `https://auth.techtales.io`.

## Variables

| Variable | Required | Default | Description                                                           |
| -------- | -------- | ------- | --------------------------------------------------------------------- |
| `APP`    | ✅       | —       | Application name. Used for resource names and the `HTTPRoute` target. |

## Vault Secret

The component expects an `ExternalSecret` that reads from the path `infra/nas/default/echo-server` in the `openbao-backend` `ClusterSecretStore`.

> **Note:** The vault path is currently hardcoded and not parameterized by `APP` or `NAMESPACE`.

The secret must contain:

| Key                          | Description                |
| ---------------------------- | -------------------------- |
| `OAUTH2_PROXY_CLIENT_ID`     | Google OIDC client ID.     |
| `OAUTH2_PROXY_CLIENT_SECRET` | Google OIDC client secret. |

## Usage

Add the component to your Flux `Kustomization` and pass the required variables via `postBuild.substitute`:

```yaml
# flux-sync.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app echo-server
spec:
  targetNamespace: default
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/oidc
  path: ./kubernetes/nas/apps/default/echo-server/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  wait: true
  interval: 30m
  retryInterval: 1m
  timeout: 5m
  dependsOn:
    - name: envoy-gateway
      namespace: networking
  postBuild:
    substitute:
      APP: *app
```

## Notes

- The OIDC provider is Google (`https://accounts.google.com`); the callback URL is the shared oauth2-proxy at `https://auth.techtales.io/oauth2/callback`.
- The `SecurityPolicy` targets the `HTTPRoute` named `${APP}` in the same namespace.
- No group- or claim-based authorization is configured — any authenticated Google user is granted access.
