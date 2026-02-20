# envoy-pocketid

Kustomize component that adds [Pocket ID](https://pocket-id.org) OIDC authentication and JWT-based authorization to an Envoy Gateway `HTTPRoute` via a `SecurityPolicy`.

## Variables

| Variable         | Required | Default            | Description                                                                                        |
| ---------------- | -------- | ------------------ | -------------------------------------------------------------------------------------------------- |
| `APP`            | ✅       | —                  | Application name. Used for resource names and the redirect/logout URL.                             |
| `NAMESPACE`      | ✅       | —                  | Kubernetes namespace to deploy into.                                                               |
| `POCKETID_GROUP` | ❌       | `privileged-users` | Pocket ID group whose members are granted access. Must match a group name configured in Pocket ID. |

## Vault Secret

The component expects an `ExternalSecret` that reads from the path `infra/kube-lab/${NAMESPACE}/${APP}` in the `openbao-backend` `ClusterSecretStore`. The secret must contain:

| Key                   | Description                                 |
| --------------------- | ------------------------------------------- |
| `OAUTH_CLIENT_ID`     | OIDC client ID registered in Pocket ID.     |
| `OAUTH_CLIENT_SECRET` | OIDC client secret registered in Pocket ID. |

## Usage

Add the component to your Flux `Kustomization` and pass the required variables via `postBuild.substitute`:

```yaml
# flux-sync.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app echo-server
  namespace: &namespace default
spec:
  targetNamespace: *namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  components:
    - ../../../../../components/envoy-pocketid
  path: ./kubernetes/main/apps/default/echo-server/app
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
      NAMESPACE: *namespace
      POCKETID_GROUP: users  # optional, defaults to privileged-users
```

## Notes

- The ID token cookie is fixed to `pocketid-token` so the JWT provider can read user claims (`display_name`, `email`, `sub`, `picture`) from it and forward them as request headers to the upstream service.
- The `groups` claim from the ID token is used for authorization. The group name is configurable via `POCKETID_GROUP`.
- `defaultAction: Deny` — all requests are denied unless they match an authorization rule.
