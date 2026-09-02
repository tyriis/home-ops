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

goto terraform-minio

- create user in data/users
- create pr and let atlantis apply

goto `secrets.techtales.io`

- create secret in `infra/kubernetes/main/volsync/<app>-<suffix>`
- copy aws credentials from created user in `infra/minio/iam/nas.techtales.io/
- create token for restic password (tools.techtales.io: 64 length)
- adjust path of restic repository
- save

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

<!-- Links -->
