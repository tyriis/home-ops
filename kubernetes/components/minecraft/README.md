# minecraft

Kustomize component that deploys a [Minecraft Java Edition](https://docker-minecraft-server.readthedocs.io) server instance using the `itzg/minecraft-server` image via the `bjw-s` app-template Helm chart.
Each instance is configured via patches applied on top of this component.

## Variables

| Variable | Required | Default | Description                                                         |
| -------- | -------- | ------- | ------------------------------------------------------------------- |
| `APP`    | ✅       | —       | Application name. Used for resource names and the HelmRelease name. |

## Vault Secrets

The component reads all secrets from the **hardcoded** path `infra/talos-flux/gaming/minecraft-java` in the `openbao-backend` `ClusterSecretStore`. The secret must contain:

| Key                       | Description                                  |
| ------------------------- | -------------------------------------------- |
| `CF_API_KEY`              | CurseForge API key for downloading mods.     |
| `PROXY_FORWARDING_SECRET` | Velocity/BungeeCord proxy forwarding secret. |
| `RCON_PASSWORD`           | RCON password for remote console access.     |

> **Note:** The vault path is shared across all Minecraft instances and is not parameterized by `APP`.

## Usage

Add the component to your app-layer `kustomization.yaml` and supply a `helm-release.patch.yaml` with instance-specific configuration (world name, memory, version, etc.). The Flux `Kustomization` must pass `APP` via `postBuild.substitute`:

```yaml
# kustomization.yaml (app directory)
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./config-map.yaml
components:
  - ../../../../../components/minecraft
configMapGenerator:
  - name: minecraft-public-survival-world-config
    files:
      - spigot.yml=config/spigot.yaml
      - paper-global.yml=config/paper-global.yaml
      - plugins.txt=config/plugins.txt
generatorOptions:
  disableNameSuffixHash: true
  annotations:
    kustomize.toolkit.fluxcd.io/substitute: disabled
patches:
  - path: ./helm-release.patch.yaml
```

The Flux `Kustomization` (e.g. in `flux-sync.yaml`) pointing to the above path should pass `APP`:

```yaml
postBuild:
  substitute:
    APP: minecraft-public-survival-world
    NAMESPACE: gaming
```

## Notes

- The component includes three `ExternalSecret` resources: `${APP}-curseforge-api-key`, `${APP}-proxy-forwarding`, and `${APP}-rcon`.
- Server type defaults to `PAPER` running Java 21. Override via `helm-release.patch.yaml`.
- Health checks use `mc-health` with a 30-second initial delay and up to 300 startup retries.
- The container runs as UID/GID `1000` with `readOnlyRootFilesystem: false` (required by the Minecraft server).
