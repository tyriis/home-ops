# minio-system

As part of the critical infrastructure it is crucial to keep dependencies low for minio, therefore external secrets from within the cluster is not used, using sops instead

## ZFS Dataset

To create a zfs dataset, we use openebs-zfs-localpv-controller.
Create a volume with full capacity, lz4 compression and 128k recordsize in our existing zfs `pool0`.
Make the volume shared (rwx possibility) and thinProvision (storage is not reserved/blocked).

```yaml
---
apiVersion: zfs.openebs.io/v1
kind: ZFSVolume
metadata:
  name: minio
spec:
  capacity: 7.14T
  fsType: zfs
  recordsize: 128k
  compression: lz4
  ownerNodeID: nas02
  poolName: pool0
  volumeType: DATASET
  shared: "yes"
  thinProvision: "yes"
```

```console
kubectl get zfsvolume minio -n openebs-system
```

```console
NAME    ZPOOL   NODEID   SIZE    STATUS   FILESYSTEM   AGE
minio   pool0   nas02    7.14T   Ready    zfs          21h
```

## persistent volume

As we now have our zfs dataset, lets move over to the persistent volume creation to bind exactly this dataset to our pv.

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:NAME    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
minio   Bound    minio    8000Gi     RWO            zfs-pool       <unset>                 9h
  name: &name minio
spec:
  accessModes:
    - ReadWriteOnce
  capacity:
    storage: 8000Gi
  claimRef:
    apiVersion: v1
    kind: PersistentVolumeClaim
    name: *name
    namespace: minio-system
  csi:
    driver: zfs.csi.openebs.io
    fsType: zfs
    volumeAttributes:
      openebs.io/poolname: pool0
    volumeHandle: *name
  nodeSelector: nas02
  persistentVolumeReclaimPolicy: Retain
  storageClassName: zfs-pool
  volumeMode: Filesystem
```

```console
kubectl get pv minio
```

```console
NAME    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
minio   8000Gi     RWO            Retain           Bound    minio-system/minio   zfs-pool       <unset>                          9h
```

## persistent volume claim

Lets proceed with our claim.

```yaml
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: &name minio
spec:
  storageClassName: zfs-pool
  volumeName: *name
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8000Gi
```

```console
kubectl get pvc minio -n minio-system
```

```console
NAME    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
minio   Bound    minio    8000Gi     RWO            zfs-pool       <unset>                 9h
```

## minio removed features in webui

[reddit thread](https://www.reddit.com/r/selfhosted/comments/1lcgq86/minio_removed_admin_features_from_the_web_ui_in)
[fork of minio console](https://github.com/OpenMaxIO/openmaxio-object-browser/issues/8)
