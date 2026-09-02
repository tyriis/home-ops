<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# System: talos-flux

## Network

<!-- This section provides an overview of the network configuration and how to test specific configurations. -->

### MS-01 LACP

To use the 2 10G NICs in the MS-01, we bond them with LCAP.

Checking if LCAP is working properly: [ServerFault](https://serverfault.com/questions/810649/how-does-one-diagnose-linux-lacp-issues-at-the-kernel-level)

```console
cat /proc/net/bonding/bond0
```
