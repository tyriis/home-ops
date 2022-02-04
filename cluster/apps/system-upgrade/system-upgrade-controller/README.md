# system-upgrade

## label nodes for upgrade manually

```sh
bash <<'EOF'
kubectl get nodes | grep Ready | for i in $(awk '{print $1}'); do
  kubectl label node $i plan.upgrade.cattle.io/k3s=true;
done
EOF
```
