# System Architecture

<!-- This section describes the high-level design of the system, including its components, their interactions, and the system's functionality. -->

The `talos-flux` cluster is running on intel NUC hardware. The choice is based on what others in the kubernetes @ home community are using and the power consumption 24/7 system has.
On one side I want to have enough computing power for heavy tasks. On the other side I dont want to spend to much money for the energy bill.

The `talos-flux` cluster uses a rook-ceph cluster of 3x 500GB NVMe drives to serve the cluster as the default storage provider.

The current network layer (CNI) is flannel but is planed to be switched in the next iteration to cilium.

As kubernetes operating system I have choosen talos from sidero, this allows to reduce OS maintenance.
