# CephPGsDamaged

## Meaning

Sometimes a Placement Group (PG) might become inconsistent. To return the PG to an active+clean state, you must first determine which of the PGs has become inconsistent and then run the pg repair command on it.

## Diagnosis

Placement group damaged, manual intervention needed

## Mitigation

Manual intervention is required!

This [page](https://docs.ceph.com/en/latest/rados/operations/pg-repair/) contains commands for diagnosing PGs and the command for repairing PGs that have become inconsistent.
