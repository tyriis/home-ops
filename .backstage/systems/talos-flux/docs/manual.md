<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->
<!-- markdownlint-disable MD029 -->

# System: talos-flux

## User Manual

<!-- This section provides detailed instructions on how to use the system, including how to perform specific tasks and how to navigate the system's user interface. -->

### Troubleshooting Guide

#### etcdserver: member not found (durring upgrade)

```console
talosctl upgrade --nodes 192.168.1.53 \
      --image ghcr.io/siderolabs/installer:v1.7.2 --wait --debug
```

```console
◲ watching nodes: [192.168.1.53]
    * 192.168.1.53: 1 error(s) occurred:
    sequence error: sequence failed: error running phase 4 in upgrade sequence: task 1/1: failed, failed to leave cluster: 2 error(s) occurred:
    failed to remove member 12511542852590030096: etcdserver: server stopped
    failed to remove member 12511542852590030096: etcdserver: member not found
```

1. reset the node after reboot

```console
talosctl -n 192.168.1.53 reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
```

when upgrading from 1.7.1 to 1.7.2 network connectivity was not established after reset, a hard power cycle was required

2. assure everything is working again

```console
talosctl etcd members
```

```console
WARNING: 1 error occurred:
        * 192.168.1.54: rpc error: code = Unimplemented desc = member list is only available on control plane nodes


NODE           ID                 HOSTNAME   PEER URLS                   CLIENT URLS                 LEARNER
192.168.1.52   4f3fb4c33808229a   talos03    https://192.168.1.53:2380   https://192.168.1.53:2379   false
192.168.1.52   5225cca9d46339f4   talos02    https://192.168.1.52:2380   https://192.168.1.52:2379   false
192.168.1.52   81048da043fcc3f3   talos01    https://192.168.1.51:2380   https://192.168.1.51:2379   false
192.168.1.51   4f3fb4c33808229a   talos03    https://192.168.1.53:2380   https://192.168.1.53:2379   false
192.168.1.51   5225cca9d46339f4   talos02    https://192.168.1.52:2380   https://192.168.1.52:2379   false
192.168.1.51   81048da043fcc3f3   talos01    https://192.168.1.51:2380   https://192.168.1.51:2379   false
192.168.1.53   4f3fb4c33808229a   talos03    https://192.168.1.53:2380   https://192.168.1.53:2379   false
192.168.1.53   5225cca9d46339f4   talos02    https://192.168.1.52:2380   https://192.168.1.52:2379   false
192.168.1.53   81048da043fcc3f3   talos01    https://192.168.1.51:2380   https://192.168.1.51:2379   false
```

3. try again

<!-- This section provides information on common problems that users may encounter when using the system, along with instructions on how to resolve these issues. -->

### Maintenance and Support

<!-- This section provides information on how to maintain and support the system, including how to perform regular backups, how to troubleshoot issues, and how to contact support if needed. -->

### Appendix

<!-- This section may include additional information, such as technical diagrams, code samples, or other supplementary material that may be useful to users or developers. -->

<!-- Overall, system documentation should provide a comprehensive and detailed reference guide for users, developers, and other stakeholders who need to understand and work with the system. -->
