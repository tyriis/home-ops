# Volsync Component Tutorial

This component provides a reusable Kustomize configuration for setting up Volsync backups with MinIO storage backend.

## Overview

The Volsync component includes:

- **PersistentVolumeClaim**: A PVC that can be restored from a ReplicationDestination
- **ReplicationSource**: Automated backup configuration using Restic with MinIO backend
- **ReplicationDestination**: Restore configuration for recovering data from backups
- **External Secret**: Integration with OpenBao for secure credential management

## Component Structure

```text
kubernetes/components/volsync/
├── README.md
├── kustomization.yaml               # Component definition
├── pvc.yaml                         # PVC with restore capability
└── minio/
    ├── external-secret.yaml         # OpenBao secret integration
    ├── kustomization.yaml           # MinIO-specific resources
    ├── replication-source.yaml      # Backup configuration
    └── replication-destination.yaml # Restore configuration
```

## Usage

### 1. Basic Usage

Include the component in your application's `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: my-app
resources:
  - ./helm-release.yaml
  - ./persistent-volume-claim.yaml

components:
  - ../../../../../components/volsync
```

### 2. Advanced Configuration

You can customize the backup behavior using environment variables:

## Configuration Variables

| Variable                      | Default              | Description                                |
| ----------------------------- | -------------------- | ------------------------------------------ |
| `APP`                         | **Required**         | Application name used for naming resources |
| `VOLSYNC_SUFFIX`              | `data`               | Suffix for generated resource names        |
| `VOLSYNC_CAPACITY`            | `5Gi`                | Size of the backup PVC                     |
| `VOLSYNC_STORAGECLASS`        | `ceph-block`         | Storage class for backup volumes           |
| `VOLSYNC_SNAPSHOTCLASS`       | `csi-ceph-blockpool` | Volume snapshot class                      |
| `VOLSYNC_CACHE_CAPACITY`      | `2Gi`                | Cache size for backup operations           |
| `VOLSYNC_CACHE_SNAPSHOTCLASS` | `ceph-block`         | Storage class for cache volumes            |
| `VOLSYNC_PUID`                | `1000`               | User ID for backup processes               |
| `VOLSYNC_PGID`                | `1000`               | Group ID for backup processes              |

## OpenBao Secret Structure

The component expects secrets to be stored in OpenBao with the following structure:

### Secret Path

```text
infra/talos-flux/volsync/${APP}-${VOLSYNC_SUFFIX}
```

### Required Secret Keys

```json
{
  "RESTIC_REPOSITORY": "s3:https://minio.example.com/backups",
  "RESTIC_PASSWORD": "your-restic-encryption-password",
  "AWS_ACCESS_KEY_ID": "minio-access-key",
  "AWS_SECRET_ACCESS_KEY": "minio-secret-key"
}
```

## Backup Schedule

The default backup schedule is **every 2 hours** (`0 */2 * * *`). You can customize this by overriding the ReplicationSource:

```yaml
# In your app's kustomization.yaml
patches:
  - target:
      group: volsync.backube
      version: v1alpha1
      kind: ReplicationSource
      name: my-app-data
    patch: |-
      - op: replace
        path: /spec/trigger/schedule
        value: "30 4 * * *"  # Daily at 4:30 AM
```

## Retention Policy

Default retention settings:

- **Hourly**: 12 snapshots
- **Daily**: 7 snapshots
- **Weekly**: 4 snapshots
- **Monthly**: 3 snapshots

## Restore Process

### 1. Create ReplicationDestination

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: my-app-restore
spec:
  trigger:
    manual: restore-manual
  restic:
    repository: my-app-volsync-minio
    destinationPVC: my-app-restored-data
    capacity: 10Gi
    storageClassName: ceph-block
    accessModes:
      - ReadWriteOnce
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
```

### 2. Monitor Restore Progress

```bash
# Check restore status
kubectl get replicationdestination my-app-restore -o yaml

# Watch restore job
kubectl get jobs -l app.kubernetes.io/name=volsync
kubectl logs -l app.kubernetes.io/name=volsync -f
```

## Troubleshooting

### Common Issues

#### Repository Lock Errors

```text
repo already locked, waiting up to 0s for the lock
```

> **Solution**: The component includes automatic unlock handling. If issues persist, manually unlock:

```bash
kubectl exec -it <volsync-pod> -- restic unlock -r $RESTIC_REPOSITORY
```

#### Permission Denied

```text
backup failed: permission denied
```

> **Solution**: Check and adjust `VOLSYNC_PUID` and `VOLSYNC_PGID` to match your application's user/group.

#### MinIO Connection Issues

```text
s3: connection failed
```

> **Solution**: Verify MinIO credentials and endpoint in OpenBao secrets.

### Debug Commands

```bash
# Check ReplicationSource status
kubectl describe replicationsource my-app-data

# View backup job logs
kubectl logs -l app.kubernetes.io/name=volsync -f

# Check external secret
kubectl describe externalsecret my-app-volsync-minio

# Verify generated secret
kubectl get secret my-app-volsync-minio -o yaml
```

## Security Considerations

1. **Encryption**: All backups are encrypted using Restic with the `RESTIC_PASSWORD`
2. **Access Control**: MinIO credentials should have minimal required permissions
3. **Network Security**: Consider using internal MinIO endpoints when possible
4. **Secret Rotation**: Regularly rotate MinIO credentials and Restic passwords

## Performance Tips

1. **Cache Size**: Increase `VOLSYNC_CACHE_CAPACITY` for large datasets
2. **Backup Timing**: Schedule backups during low-usage periods
3. **Retention**: Adjust retention policy based on recovery requirements
4. **Parallel Jobs**: Avoid running multiple backups simultaneously on the same node
