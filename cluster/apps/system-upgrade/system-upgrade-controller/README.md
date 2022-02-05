# system-upgrade

## :detective:&nbsp; Troubleshooting

Assure that nodes are labeled with `plan.upgrade.cattle.io/k3s=true` otherwise upgrade will not trigger.
Nodes should be auto labeled by [label-nodes](https://github.com/tyriis/flux.k3s.cluster/cluster/apps/system-upgrade/label-nodes/)

With the snippet you can label all your nodes manual

```bash
bash <<'EOF'
kubectl get nodes | grep Ready | for i in $(awk '{print $1}'); do
  kubectl label node $i plan.upgrade.cattle.io/k3s=true;
done
EOF
```
