# ETCD Database Fragmentation Troubleshooting

## Overview

This runbook provides steps for addressing high database fragmentation in etcd clusters, which can lead to degraded performance and increased resource utilization.

## Prerequisites

- `talosctl` admin access to the cluster

## Steps

1. Check etcd Database Fragmentation

   Use the following command to get the current database size and in-use size:

   ```bash
   talosctl -n <control-plane-node> etcd status
   ```

   Look for the "DB SIZE" and "IN USE" columns. If the "in use/db size" ratio is less than 0.5 (i.e., less than 50%), fragmentation is considered high and defragmentation is recommended.

2. Defragment the etcd Database

   Run the defragmentation command on each control plane node, one at a time:

   ```bash
   talosctl -n <control-plane-node> etcd defrag
   ```

   Replace `<control-plane-node>` with the IP or hostname of each control plane node.

   > "Note: Defragmentation is resource-intensive and temporarily blocks reads and writes for the node being defragmented. Always run it on one node at a time to avoid impacting cluster availability"

## Verification

1. Verify Improvement

   After defragmentation, run the status command again:

   ```bash
   talosctl -n <control-plane-node> etcd status
   ```

   The "DB SIZE" should now closely match the "IN USE" size, and the fragmentation ratio should be much higher (closer to 1.0 or 100%).

## Troubleshooting

### Common Issues

1. Defragmentation Fails
   - Symptoms: Command times out or returns error
   - Cause: Cluster instability or resource constraints
   - Resolution:

     If etcd is crashing or not running, check logs using:

     ```bash
     talosctl -n <control-plane-node> logs etcd
     ```

2. High Fragmentation Returns Quickly
   - Symptoms: Fragmentation ratio rises shortly after defragmentation
   - Cause: High write load or frequent object changes
   - Resolution:

     If your etcd database frequently approaches its space quota, consider increasing the quota in your Talos machine configuration under the etcd.extraArgs.quota-backend-bytes setting, then reboot the node for the change to take effect.

     Regularly monitor etcd health and perform defragmentation as part of routine maintenance, especially for clusters with high churn (frequent writes/deletes).

     Always maintain regular etcd backups to safeguard against database corruption or other failures.

     ```bash
     # Schedule regular defragmentation with a CronJob
     # Consider adjusting compaction settings in etcd configuration
     ```

## References

- Related documentation
- External resources
  - [talos etcd Maintenance](https://www.talos.dev/v1.9/advanced/etcd-maintenance/)
- Support contacts
