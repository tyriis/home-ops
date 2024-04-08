# rook-ceph

## overview

The `rook-ceph` component is a storage operator for Kubernetes, leveraging the power of Ceph, a highly scalable and resilient storage system.
It abstracts the complexity of deploying and managing Ceph storage clusters, making it easy to provision, scale, and maintain Ceph within your Kubernetes environment.
With `rook-ceph`, you can leverage Ceph's capabilities for object storage, block storage, and file systems in a cloud-native way.
It provides seamless integration with Kubernetes, allowing you to use standard Kubernetes primitives for managing storage.
This component is part of Rook, an open-source cloud-native storage orchestrator, providing the platform, framework, and support for a diverse set of storage solutions to natively integrate with cloud-native environments.

## setup

Setting up `rook-ceph` involves a few steps to ensure a successful deployment on your Kubernetes cluster.

First, you need to install the Rook operator. This can be done by applying the Rook operator manifest using `kubectl`.

Next, you need to create a Rook cluster. This involves defining a `CephCluster` resource in a YAML file, specifying the desired configuration for your Ceph storage cluster.

Once the Rook operator and the Ceph cluster are up and running, you can start provisioning storage.
Rook allows you to define `CephBlockPool`, `CephFilesystem`, and `CephObjectStore` resources to create block devices, file systems, and S3-compatible object stores, respectively.

Remember to monitor the status of your `rook-ceph` deployment regularly. You can use the `ceph status` command for this purpose.

Detailed instructions and examples can be found in the official Rook documentation. Always ensure your Kubernetes environment meets the prerequisites before starting the setup.

## usage

Using `rook-ceph` involves interacting with the storage resources it provides.

For block storage, you can create a PersistentVolumeClaim against a StorageClass that uses the `rook-ceph-block` provisioner. This will dynamically provision a PersistentVolume backed by a Rook Ceph block device.
