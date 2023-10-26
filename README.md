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

| Tool                                                                              | Role                                                                                     |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [talos][talos-url]                                                                | Linux designed for Kubernetes – secure, immutable, and minimal.                          |
| [Flux2][flux-url]                                                                 | Kubernetes GitOps engine                                                                 |
| [Terraform][terraform-url]                                                        | Infrastructure automation to provision and manage resources in any cloud or data center. |
| [Cloudflare](https://www.cloudflare.com/)                                         | DNS and tunnels to allow external traffic                                                |
| [RenovateBot](https://www.whitesourcesoftware.com/free-developer-tools/renovate/) | Automated dependency updates.                                                            |
| [GitHub](https://github.com)                                                      | Code Hosting and job runnner                                                             |

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

See the [open issues](https://github.com/tyriis/home-ops/issues) for a full list of proposed features (and known issues).

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

[terraform-url]: https://github.com/hashicorp/terraform/releases
[terraform-shield]: https://img.shields.io/badge/terraform-1.x-844fba?style=for-the-badge&logo=terraform
[talos-url]: https://www.talos.dev/
[talos-shield]: https://img.shields.io/badge/Talos-v1.3.6-fa371a?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAW9yTlQBz6J3mgAABGRJREFUOMttlE+IXWcZxn/P+51zz52ZTCYNiQYnGkUxlVIl/glGWqJWi03SGruQLsQsWiiktCBCXUjqTmitXYjQjtiVigSRVhorGqf+wYpU07hwkagwqSSTTu/8u/eee++Zc873vS6iaYq+y3fx43ng4SduOH8acORom8tKbXfHKISfAbnH/Bgp1hq0hrMNtyHI9Ui8zrDrsMczKAWl3aMxCzZMb+MqsAreA+85cbOBXgsVe9ji+1753b6V8Cfs/wABHwvfYo6RjlPqsIbAmqG1AOsGGwlKwwfh0z6yu71mzifgruvArP5aDkC7DiZALKr1fyn6cZXhp2l76+YAwiwQq5iH3I7LeI3AIoD6Ef/qfxLmp4+T9eLR0GsPWM85+807r1CyqFK3eWJfmuA+FowMG3YTW3q3j/2Qj/zsLx/3Za0ZbHQ+7BvZ0fTbjCwefGmW8dQjju+0OvvSnff97qKHzq9i1An38NGYVa/JO+BG1s6mFOLHkO+Q+dnPfjGQetl+7/qCZ3FdN/P7jKW1ob9j7js0etbb7EnbmvlyMzs6TwxrSnaoiFPPpZBwidpT5po6lOS9oPTXdpLfFPL47dRob+qEb4z+9q6hNXM7yX72lZ+nsjgVy/xTTcVDsV+8wbC4wDD/UF12Ztph4WnQIQ3zaYbFBzXoXmB9esVG3YfSqPgkZTjVff7zL07vu4oAqo/Mg/kUVedZEp/w5HdYsIfl6ag7n3Gl7yFIsgcNfm3oBY98V+aLydIf6qnmgSxaNf2XZTKA7rkrTN77vgn4D5TsHnMdSMZVSLNyn3UiAnfCbFLa5mhZrgMudgX0w+6wqDpL/7w2m//uJ00y3BUMMFdM1goyF+54Dg6SOziOSXh0RHRloLcOu7/7ZtrGp2OrE21rr8dW51Pje1OjQWyyQWwzYhtE3R2kphjE1t7ZtuF829rrddKJOoaZwe5brwGX3/4BruSVKnXurxXuat2e2aSzUnlxS+N2qUX9GlRJmhibtbhUY7dsxXyl8fBM4+HIWH7/hShd3nUr9pgfYqqZvXcLPVahX2wFX2iJeydo/0h2bmQ2rpAqiVLFeILOTQj7y2DzjbSwBS/Wbqd2m9/7QCPsYTs/N7RwspRdbLBHN1MYbpoO9s22bwR7eQN83Yy+jCYl3zR7ecPCXN/s4KqF4ch4tDQujoyT3yo0l81k9FdaewL55ehaGloRplJzl5Eum/zVltxEwlzEDMtlr0a0nNw+NzA7vSf6UsAfdGPvTsq+bvTh6T23AXp/ULNoxBe+sPbnkz/Z9fECOCOX5zE79p75cf33lc7TIh5t4Q7gH/ctv/K/+npy/jB9M3qmIz3lO1ZVPLew63Z6ylhVzqoyrgbxx5UZ1pQ//4aKm3oqjvTV4an5w2/q68aES11ne2NXHH7UifZKFFRm4AI5LYGChOF/SvIfB/nyOMCO+k3GWyp/fd/t6Nqvm0RVptwdCtCZaw62Y8LrWY9qjalWVA7pqUu/uc74N6DdUmr/G0k5AAAAAElFTkSuQmCC
[pre-commit-url]: https://github.com/pre-commit/pre-commit
[pre-commit-shield]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&style=for-the-badge
[renovate-dashboard-url]: https://app.renovatebot.com/dashboard#github/tyriis/home-ops
[renovate-shield]: https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot&style=for-the-badge
[taskfile-url]: https://taskfile.dev/
[taskfile-shield]: https://img.shields.io/badge/Taskfile-Enabled-brightgreen?style=for-the-badge&logo=task
[cloudflare-url]: https://dash.cloudflare.com/
[cloudflare-shield]: https://img.shields.io/badge/cloudflare-dns-F38020?logo=cloudflare&style=for-the-badge&logoColor=white
[commits-url]: https://github.com/tyriis/home-ops/commits/main
[commits-shield]: https://img.shields.io/github/last-commit/tyriis/home-ops?logo=github&style=for-the-badge
[letsencrypt-url]: https://letsencrypt.org/
[renovate-url]: https://github.com/renovatebot/renovate
[flux-url]: https://fluxcd.io/
[k8s-at-home-url]: https://k8s-at-home.com/
[flux-home-cluster-url]: https://github.com/tyriis/flux.home-cluster
[flux-k3s-home-url]: https://github.com/tyriis/flux.k3s.home
[flux-pi-k3s-home-url]: https://github.com/tyriis/flux.pi-k3s.home
[megalinter-badge]: https://github.com/tyriis/home-ops/workflows/MegaLinter/badge.svg?branch=main
[megalinter-url]: https://github.com/tyriis/home-ops/actions/workflows/mega-linter.yaml?query=branch%3Amain
