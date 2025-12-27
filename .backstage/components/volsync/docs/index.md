# Backup-system - Volsync

## Configure

configure persistence with existing claim in helm release:

```yaml
persistence:
  config:
    existingClaim: ${APP}-data
```

configure `flux-sync.yaml` of the app:

```yaml
spec:
  components:
    - ../../../../../components/volsync
  dependsOn:
    - name: volsync
      namespace: backup-system
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_SUFFIX: data
```

goto `secrets.techtales.io`

- create secret in `infra/talos-flux/volsync/<app>-<suffix>`
- check another volsync secret for structure
- create token (it-tools..)
  - copy as is
- adjust path and save

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

<!-- Links -->
