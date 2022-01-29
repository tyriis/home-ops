node.longhorn.io/create-default-disk=true

# Longhorn default-disk
will be added to worker01, worker02, and worker04 because of min vcpu and

````bash
kubectl label nodes k3s-worker01 node.longhorn.io/create-default-disk=true
kubectl label nodes k3s-worker02 node.longhorn.io/create-default-disk=true
kubectl label nodes k3s-worker04 node.longhorn.io/create-default-disk=true
```

## Todo
- [] move node labeling to a kubernetes job or to bootstrap terraform
