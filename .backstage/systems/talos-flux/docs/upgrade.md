<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->
<!-- markdownlint-disable MD029 -->

# System: talos-flux

## Upgrades

<!-- This section provides detailed instructions on how upgrade the system. -->

### Upgrade talos version

approx. 30m

Steps:

- checkout branch with increased versions
- copy 1 example of existing config
- generate new config with

```shell
task talos:config
```

- compare changes
- perform upgrade on all nodes with

```shell
task talos:upgrade cluster=talos-flux hostname=192.168.1.xx
```

- check dashboard

```shell
task talos:dashboard:talosxx
```

### Upgrade kubernetes version

approx. 10m

Steps:

- checkout branch with increased versions
- generate new config with

```shell
task talos:config
```

- perform upgrade on all nodes with

```shell
task talos:kubelet:upgrade cluster=talos-flux hostname=talos01 ip=192.168.1.xx
```
