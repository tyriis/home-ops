<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# System: talos-flux

## Introduction

<!-- This section provides an overview of the system, its purpose, and its intended users. -->

The `talos-flux` represents a Kubernetes cluster built upon the robust foundation of [Talos Linux](https://www.talos.dev/). This cluster operates efficiently on low-power hardware within the confines of a HomeLab environment.

Its primary mission is to serve as the hosting platform for a comprehensive suite of applications essential for managing a modern smart home and catering to the digital needs of a family.

## System Architecture

<!-- This section describes the high-level design of the system, including its components, their interactions, and the system's functionality. -->

The `talos-flux` operates on Intel NUC hardware, a decision influenced by the preferences of the [kubernetes@home community](https://discord.com/invite/k8s-at-home) and the imperative consideration of minimizing 24/7 power consumption. This choice strikes a balance between computing power to handle resource-intensive tasks and the desire to keep energy expenses in check.

Within the `talos-flux`, a robust storage infrastructure is provided by a [Rook-Ceph cluster](https://rook.io/) comprising three 500GB NVMe drives. This configuration serves as the default storage solution for the entire cluster, ensuring efficient data management.

Currently, the network layer, Container Network Interface (CNI), is implemented using Flannel. However, there are plans to transition to Cilium in the upcoming iteration, further enhancing network performance and security.

For the Kubernetes operating system, the deliberate choice is [Talos Linux](https://www.talos.dev/) from Sidero. This decision is driven by the desire to streamline and simplify OS maintenance, a crucial factor in ensuring the cluster's long-term stability and manageability.

## Technical Specifications

<!-- This section provides detailed information about the system's technical specifications, such as the hardware and software requirements, network topology, and any other technical  details that are relevant to the system's operation. -->

### Hardware

<!-- This section provides detailed information about the system's hardware. -->

| Device           | CPU       | OS    | OS Disk   | Data Disk              | RAM  | Purpose               |
| ---------------- | --------- | ----- | --------- | ---------------------- | ---- | --------------------- |
| Intel NUC7i7DNHE | i7-8650U  | Talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | Talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | Talos | 500GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC10I7FNH | i7-10710U | Talos | 500GB SSD | -                      | 32GB | worker                |

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
| Harbor  | Container registry and mirror              |

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
| traefik | 192.168.1.80 |
