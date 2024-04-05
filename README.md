<!-- markdownlint-disable MD041 -->
<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD051 -->

<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->

[![taskfile][taskfile-shield]][taskfile-url]
[![pre-commit][pre-commit-shield]][pre-commit-url]
[![renovate][renovate-shield]][renovate-dashboard-url]
[![commits][commits-shield]][commits-url]
[![talos][talos-shield]][talos-url]
[![kubernetes][kubernetes-shield]][kubernetes-url]
[![terraform][terraform-shield]][terraform-url]
[![cloudflare][cloudflare-shield]][cloudflare-url]

<!-- PROJECT LOGO -->
<!--<br />
<div align="center">
  <img src="https://cncf-branding.netlify.app/img/projects/flux/horizontal/color/flux-horizontal-color.svg" alt="Logo" width="200" heigh="103">
</div>-->
<br />

# Kubernetes GitOps Cluster

- 💼 managed with [Flux2][flux-url] and [Terraform][terraform-url]
- 🤖 updated by [RenovateBot][renovate-url]
- 🔐 secured by [Let's Encrypt][letsencrypt-url]

<details>
  <summary style="font-size:1.2em;">Table of Contents</summary>
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [About The Project](#about-the-project)
  - [🧰 Tools and Technologies](#%F0%9F%A7%B0-tools-and-technologies)
  - [📖 Overview](#-overview)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
- [Roadmap](#roadmap)
- [🕵️ Troubleshooting](#%EF%B8%8F-troubleshooting)
  - [Stuck HelmRelease](#stuck-helmrelease)
- [Quality](#quality)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
</details>

<!-- ABOUT THE PROJECT -->

## About The Project

👋 Hello and welcome to my Home Lab GitOps Cluster Configuration!

In this project, I am thrilled to share with you the automated configuration of my home infrastructure. As an ardent believer in continuous learning, I embrace every opportunity to challenge myself and expand my knowledge horizon.
Through this venture, I aim to not only streamline and automate my daily tasks but also encourage collaboration and knowledge sharing within the community.

This is a private project heavily inspired by the great [k8s-at-home][k8s-at-home-url] community.

Let's take a glimpse into the evolution of this project:

- The Foundation: [flux.home-cluster][flux-home-cluster-url] starting with a first iteration and learn Flux and GitOps principles with some old hardware.
- The Minimal Redundancy Edition: [flux.pi-k3s.home][flux-pi-k3s-home-url] starting a new project with a Raspberry Pi based GitOps Flux Cluster, with three control planes.
- The Merge: [flux.k3s.home][flux-k3s-home-url] after a successfull testing phase I merged both projects into one cluster.

By making my findings and work accessible to all, I strongly believe in the principle that knowledge should be free, empowering individuals to avoid repetitive endeavors and instead focus on new and exciting challenges.

Join me on this exciting journey as we delve into the realm of Kubernetes and GitOps, uncovering new insights and finding innovative ways to enhance our setups. Let's embrace the spirit of collaboration and empower each other to achieve more.

Happy automating, learning, and exploring!

<p align="right">(<a href="#top">back to top</a>)</p>

### 🧰 Tools and Technologies

Here is the list of tools and technologies I am using in this project.

| Tool                              | Role                                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------- |
| [talos][talos-url]                | Linux designed for Kubernetes – secure, immutable, and minimal.                          |
| [Flux2][flux-url]                 | Kubernetes GitOps engine                                                                 |
| [Terraform][terraform-url]        | Infrastructure automation to provision and manage resources in any cloud or data center. |
| [Cloudflare][cloudflare-homepage] | DNS and tunnels to allow external traffic                                                |
| [RenovateBot][renovate-url]       | Automated dependency updates.                                                            |
| [GitHub][github-url]              | Code Hosting and job runnner                                                             |
| [Backstage][backstage-url]        | Documentation with backstage developer portal                                            |

### 📖 Overview

#### Hardware

| Device           | CPU       | OS    | OS Disk     | Data Disk              | RAM  | Purpose               |
| ---------------- | --------- | ----- | ----------- | ---------------------- | ---- | --------------------- |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500 GB SSD  | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500 GB SSD  | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos | 500 GB SSD  | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC10I7FNH | i7-10710U | talos | 500 GB NVMe | -                      | 32GB | worker                |

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->

## Getting Started

TBD

### Prerequisites

- mozilla sops
- age

### Installation

TBD

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->

## Usage

TBD

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- ROADMAP -->

## Roadmap

- [ ] Complete README.md
- [ ] Add Changelog
- [ ] Add GitHub Pages

See the [open issues][github-issues] for a full list of proposed features (and known issues).

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->

## 🕵️ Troubleshooting

### Stuck HelmRelease

[discussion](https://github.com/fluxcd/flux2/issues/1878)

example:

```bash
➜ flux suspend hr -n networking traefik
► suspending helmreleases traefik in networking namespace
✔ helmreleases suspended
```

```bash
➜ flux resume hr -n networking traefik
► resuming helmreleases traefik in networking namespace
✔ helmreleases resumed
◎ waiting for HelmRelease reconciliation
✔ HelmRelease reconciliation completed
✔ applied revision 10.9.1
```

<p align="right">(<a href="#top">back to top</a>)</p>

## Quality

[![megalinter][megalinter-badge]][megalinter-url]

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

<!-- Links -->

[backstage-url]: https://backstage.spotify.com/
[cloudflare-homepage]: https://www.cloudflare.com/
[flux-home-cluster-url]: https://github.com/tyriis/flux.home-cluster
[flux-k3s-home-url]: https://github.com/tyriis/flux.k3s.home
[flux-pi-k3s-home-url]: https://github.com/tyriis/flux.pi-k3s.home
[flux-url]: https://fluxcd.io/
[github-url]: https://github.com
[github-issues]: https://github.com/tyriis/home-ops/issues
[k8s-at-home-url]: https://k8s-at-home.com/
[letsencrypt-url]: https://letsencrypt.org/
[renovate-dashboard-url]: https://app.renovatebot.com/dashboard#github/tyriis/home-ops
[megalinter-badge]: https://github.com/tyriis/home-ops/workflows/MegaLinter/badge.svg?branch=main
[megalinter-url]: https://github.com/tyriis/home-ops/actions/workflows/mega-linter.yaml?query=branch%3Amain

<!-- Badges -->

[taskfile-shield]: https://img.shields.io/badge/Taskfile-Enabled-brightgreen?style=for-the-badge&logo=task
[taskfile-url]: https://taskfile.dev/
[pre-commit-shield]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?style=for-the-badge&logo=pre-commit
[pre-commit-url]: https://github.com/pre-commit/pre-commit
[renovate-shield]: https://img.shields.io/badge/renovate-enabled-brightgreen?style=for-the-badge&logo=renovatebot
[renovate-url]: https://www.whitesourcesoftware.com/free-developer-tools/renovate/
[commits-shield]: https://img.shields.io/github/last-commit/tyriis/home-ops?style=for-the-badge&logo=github
[commits-url]: https://github.com/tyriis/home-ops/commits/main
[talos-shield]: https://img.shields.io/badge/Talos-1.6.7-ff7300?style=for-the-badge&logo=talos
[talos-url]: https://www.talos.dev/
[kubernetes-shield]: https://img.shields.io/badge/kubernetes-1.29.3-326CE5?style=for-the-badge&logo=kubernetes
[kubernetes-url]: https://kubernetes.io/releases/
[terraform-shield]: https://img.shields.io/badge/terraform-1.x-844fba?style=for-the-badge&logo=terraform
[terraform-url]: https://github.com/hashicorp/terraform/releases
[cloudflare-shield]: https://img.shields.io/badge/cloudflare-dns-F38020?style=for-the-badge&logo=cloudflare
[cloudflare-url]: https://dash.cloudflare.com/
