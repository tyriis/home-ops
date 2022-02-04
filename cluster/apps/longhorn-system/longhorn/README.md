# Longhorn default-disk

will be added to worker01, worker02, and worker04 because of min vcpu

```bash
kubectl label nodes k3s-worker01 node.longhorn.io/create-default-disk=true
kubectl label nodes k3s-worker02 node.longhorn.io/create-default-disk=true
kubectl label nodes k3s-worker04 node.longhorn.io/create-default-disk=true
```

## check k8s environment

```bash
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v1.1.1/scripts/environment_check.sh | bash
```

## test

```bash
kubectl create -f https://raw.githubusercontent.com/longhorn/longhorn/v1.2.3/examples/pod_with_pvc.yaml
```

remove afterwards

```bash
kubectl delete -f https://raw.githubusercontent.com/longhorn/longhorn/v1.2.3/examples/pod_with_pvc.yaml
```

## Todo

- [] move node labeling to a kubernetes job or to bootstrap terraform
- [] assure iscsi is installed, enabled and started on all devices
- [] assure <https://longhorn.io/kb/troubleshooting-volume-with-multipath/> is applied (also fixes: apparently in use by the system; will not make a filesystem here!)
