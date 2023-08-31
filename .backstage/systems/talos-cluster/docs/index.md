<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# System: talos-cluster

## Introduction

<!-- This section provides an overview of the system, its purpose, and its intended users. -->

The `talos-cluster` is a kubernetes cluster based on [Talos linux](https://www.talos.dev/).
It is running on low power hardware as a HomeLab.

Its main purpose is to host all applications the smart home and a digital family need.

The `talos-cluster` represents a Kubernetes cluster built upon the robust foundation of [Talos Linux](https://www.talos.dev/). This cluster operates efficiently on low-power hardware within the confines of a HomeLab environment.

Its primary mission is to serve as the hosting platform for a comprehensive suite of applications essential for managing a modern smart home and catering to the digital needs of a family.

## System Architecture

<!-- This section describes the high-level design of the system, including its components, their interactions, and the system's functionality. -->

The `talos-cluster` operates on Intel NUC hardware, a decision influenced by the preferences of the [kubernetes@home community](https://discord.com/invite/k8s-at-home) and the imperative consideration of minimizing 24/7 power consumption. This choice strikes a balance between computing power to handle resource-intensive tasks and the desire to keep energy expenses in check.

Within the `talos-cluster`, a robust storage infrastructure is provided by a [Rook-Ceph cluster](https://rook.io/) comprising three 500GB NVMe drives. This configuration serves as the default storage solution for the entire cluster, ensuring efficient data management.

Currently, the network layer, Container Network Interface (CNI), is implemented using Flannel. However, there are plans to transition to Cilium in the upcoming iteration, further enhancing network performance and security.

For the Kubernetes operating system, the deliberate choice is [Talos Linux](https://www.talos.dev/) from Sidero. This decision is driven by the desire to streamline and simplify OS maintenance, a crucial factor in ensuring the cluster's long-term stability and manageability.

## Technical Specifications

<!-- This section provides detailed information about the system's technical specifications, such as the hardware and software requirements, network topology, and any other technical  details that are relevant to the system's operation. -->

### Hardware

<!-- This section provides detailed information about the system's hardware. -->

| Device           | CPU       | OS    | OS Disk   | Data Disk              | RAM  | Purpose               |
| ---------------- | --------- | ----- | --------- | ---------------------- | ---- | --------------------- |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC10I7FNH | i7-10710U | talos | 500GB SSD | -                      | 32GB | worker                |

To install inital install talos on the NUC devices, I currently use an USB thumb drive.

### Cloud Services

<!-- This section provides detailed information about the system's cloud services. -->

The `talos-flux` cluster rely on a few cloud services

| Service       | Use                                                       | Cost         |
| ------------- | --------------------------------------------------------- | ------------ |
| GitHub        | Repository hosting and continuous integration/deployments | Free         |
| Cloudflare    | Domain, DNS and proxy management, tunnel access           | $36.00/ year |
| Grafana Cloud | Loki log mirror target                                    | Free         |

### Local Services

<!-- This section provides detailed information about the system's local services. -->

| Service | Use                                        |
| ------- | ------------------------------------------ |
| Vault   | Secret Managment                           |
| Minio   | S3 backend for terraform states and backup |

### Software

<!-- This section provides detailed information about the system's software requirements. -->

The following dependencies need to be installed on the system for the inital setup and maintenance

| Tool                                                        | Role                                                                     |
| ----------------------------------------------------------- | ------------------------------------------------------------------------ |
| [kubectl](https://kubernetes.io/docs/tasks/tools/)          | The kubernetes cli                                                       |
| [go-task](https://taskfile.dev/)                            | Task runner to execute Taskfile commands                                 |
| [pre-commit](https://pre-commit.com/)                       | A framework for managing and maintaining multi-language pre-commit hooks |
| [sops](https://github.com/mozilla/sops)                     | SOPS: Secrets OPerationS                                                 |
| [age](https://github.com/FiloSottile/age)                   | Simple, modern and secure file encryption tool                           |
| [flux](https://fluxcd.io/flux/get-started/)                 | Continuous and progressive delivery solutions for Kubernetes             |
| [talosctl](https://www.talos.dev/v1.4/learn-more/talosctl/) | The Talos cli                                                            |
| [talhelper](https://github.com/budimanjojo/talhelper)       | Creating Talos cluster in GitOps way                                     |
| [git](https://git-scm.com/)                                 | Yeah this is just git, I am sure it is already installed :)              |

### Network

<!-- This section provides detailed information about the system's network requirements and configurations. -->

| Host    | IP           |
| ------- | ------------ |
| VIP     | 192.168.1.50 |
| talos01 | 192.168.1.51 |
| talos02 | 192.168.1.52 |
| talos03 | 192.168.1.53 |
| talos04 | 192.168.1.54 |

## Installation and Configuration

<!-- This section describes the steps required to install and configure the system, including any prerequisites and dependencies. -->

### setup sops key

<!-- This section describes the steps required to configure and use sops with age, including any prerequisites and dependencies. -->

### prepare talos config

**talhelper** should be available on the system

```bash
➜ talhelper -v
```

??? prompt "output"

    ```bash
    talhelper version 1.7.3
    ```

Generate secrets with talhelper:

```bash
talhelper gensecret > talsecret.sops.yaml
```

Encrypt the generated secrets with sops:

```bash
sops -e -i talsecret.sops.yaml
```

Create the `talconfig.yaml`, check [examples](https://github.com/budimanjojo/talhelper).

Generate the talos configuration files:

```bash
talhelper genconfig
```

<details><summary>Output</summary>

```bash
➜ talhelper genconfig
[SOPS]   WARN[0000] Found possibly unencrypted comment in file. This is to be expected if the file being decrypted was created with an older version of SOPS.  comment=" yamllint disable"
generated config for kube-nas in ./clusterconfig/kube-nas-kube-nas.yaml
generated client config in ./clusterconfig/talosconfig
generated .gitignore file in ./clusterconfig/.gitignore
```

</details>

You should have the following folder structure now:

```console
.
├── clusterconfig
│   ├── .gitignore
│   ├── talos-flux-talos01.yaml
│   ├── talos-flux-talos02.yaml
│   ├── talos-flux-talos03.yaml
│   ├── talos-flux-talos04.yaml
│   └── talosconfig
├── talconfig.yaml
└── talsecret.sops.yaml
```

### first node (control-plane)

Download [talos][talos-url]

Flash with a tool like [etcher][etcher-url]

Boot the 1st node from usb drive.

!!! note

    Assure the IP on the 1st node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.51 \
   --file clusterconfig/talos-flux-talos01.yaml
```

<details><summary>Output</summary>

```bash
TODO: add command output
```

</details>

Bootstrap the control-plane

```bash
talosctl bootstrap --nodes 192.168.1.51
```

### kubeapi access

In order to be able to access the kubernetes cluster api, run:

```bash
talosctl kubeconfig \
   --talosconfig=infra/talos/clusterconfig/talosconfig \
   --nodes 192.168.1.51 \
   --endpoints 192.168.1.51 \
   --force
```

The kubeconfig should be created and you should be able to access the cluster with the following command:

```bash
kubectl get nodes
```

<details><summary>Output</summary>

```bash
NAME      STATUS   ROLES           AGE    VERSION
talos01   Ready    control-plane   12s    v1.26.3
```

</details>

### more nodes

Lets add the other 3 nodes to our cluster:

Boot the 2nd node from usb drive.

!!! note

    Assure the IP on the 2nd node matches the configuration from your configuration

On your workstation run:

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.52 \
   --file clusterconfig/talos-flux-talos02.yaml
```

Repeat the steps for node 3 and 4

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.53 \
   --file clusterconfig/talos-flux-talos03.yaml
```

```bash
talosctl apply-config --insecure \
   --nodes 192.168.1.54 \
   --file clusterconfig/talos-flux-talos04.yaml
```

Lets check our nodes:

```bash
kubectl get nodes
```

<details><summary>Output</summary>

```bash
NAME      STATUS   ROLES           AGE    VERSION
talos01   Ready    control-plane   6m     v1.26.3
talos02   Ready    control-plane   4m     v1.26.3
talos03   Ready    control-plane   2m     v1.26.3
talos04   Ready    <none>          9s     v1.26.3
```

</details>

### Install metrics server

Create the following file:

```yaml linenums="1" title="metrics-server/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: metrics-server
    repo: https://kubernetes-sigs.github.io/metrics-server
    version: 3.8.4
    releaseName: metrics-server
    namespace: kube-system
    valuesFile: values.yaml
commonAnnotations:
  meta.helm.sh/release-name: metrics-server
  meta.helm.sh/release-namespace: kube-system
commonLabels:
  app.kubernetes.io/managed-by: Helm
```

!!! note

    For the latest release version check the repo!

Create the values file:

```yaml linenums="1" title="metrics-server/values.yaml"
---
metrics:
  enabled: false
serviceMonitor:
  enabled: false
```

Render and apply the manifests:

```bash
kubectl kustomize --enable-helm metrics-server | kubectl apply -f -
```

### Install kubelet-csr-approver

Create the following file:

```yaml linenums="1" title="kubelet-csr-approve/kustomization.yaml"
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
  - name: kubelet-csr-approver
    repo: https://postfinance.github.io/kubelet-csr-approver
    version: 1.0.0
    releaseName: kubelet-csr-approver
    namespace: kube-system
    valuesFile: values.yaml
commonAnnotations:
  meta.helm.sh/release-name: kubelet-csr-approver
  meta.helm.sh/release-namespace: kube-system
commonLabels:
  app.kubernetes.io/managed-by: Helm
```

!!! note

    For the latest release version check the repo!

Create the values file:

```yaml linenums="1" title="kubelet-csr-approve/values.yaml"
---
providerRegex: |
  ^(kube-nas)$
```

Render and apply the manifests:

```bash
kubectl kustomize --enable-helm kubelet-csr-approver | kubectl apply -f -
```

### Install flux

<!-- This section provides detailed instructions on how to install flux, including how to perform specific tasks and how to navigate the system's user interface. -->

## User Manual

<!-- This section provides detailed instructions on how to use the system, including how to perform specific tasks and how to navigate the system's user interface. -->

### Troubleshooting Guide

<!-- This section provides information on common problems that users may encounter when using the system, along with instructions on how to resolve these issues. -->

### Maintenance and Support

<!-- This section provides information on how to maintain and support the system, including how to perform regular backups, how to troubleshoot issues, and how to contact support if needed. -->

### Appendix

<!-- This section may include additional information, such as technical diagrams, code samples, or other supplementary material that may be useful to users or developers. -->

<!-- Overall, system documentation should provide a comprehensive and detailed reference guide for users, developers, and other stakeholders who need to understand and work with the system. -->

[talos-url]: https://github.com/siderolabs/talos/releases
[etcher-url]: https://etcher.balena.io/

<!--
## something

## something else

??? success
   Content.

??? warning classes
   Content.

::uml:: format="png" classes="uml myDiagram" alt="My super diagram placeholder" title="My super diagram" width="300px" height="300px"
  Goofy ->  MickeyMouse: calls
  Goofy <-- MickeyMouse: responds
::end-uml::

```yaml linenums="1" title="test.yaml" hl_lines="2 3"
test:
   a: 123
   b: 213
```

:fontawesome-regular-face-laugh-wink:

:octicons-heart-fill-24:{.heart}

Lorem ipsum[^1] dolor sit amet, consectetur adipiscing elit.[^2]

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

:fontawesome-regular-face-laugh-wink:

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

!!! note "Phasellus posuere in sem ut cursus"

   Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
   nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
   massa, nec semper lorem quam in massa.

[^1]: Lorem ipsum dolor sit amet, consectetur adipiscing elit.

[^2]:
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla et euismod
    nulla. Curabitur feugiat, tortor non consequat finibus, justo purus auctor
    massa, nec semper lorem quam in massa.
-->
