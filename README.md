<!-- markdownlint-disable MD041 -->
<!-- markdownlint-disable MD033 -->

<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->

[![pre-commit][pre-commit-shield]][pre-commit-url]
[![renovate][renovate-shield]][renovate-dashboard-url]
[![taskfile][taskfile-shield]][taskfile-url]
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

<br />
<!-- TABLE OF CONTENTS -->
<details>
  <summary style="font-size:1.2em;">📑 Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#goals">Goals</a></li>
        <li><a href="#toolbox-tools-and-technologies">🧰 Tools and Technologies</a></li>
        <li><a href="#book-overview"> 📖 Overview</a></li>
      </ul>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#🕵️-troubleshooting">🕵️ Troubleshooting</a></li>
  </ol>
</details>
<br />

<!-- ABOUT THE PROJECT -->

## About The Project

👋 Hello and welcome to my project. This is a private project heavily inspired by the great [k8s-at-home][k8s-at-home-url] community. I want to share my work and findings but also my frustrations with you.

This project is the result of a merge from my previous iterations [flux.home-cluster][flux-home-cluster-url], [flux.k3s.home][flux-k3s-home-url] and [flux.pi-k3s.home][flux-pi-k3s-home-url].

### Goals

- Automate my home and home infrastructure.
- Learn new things everyday.
- Challenge myself.
- Share my findings and work with you. (cause knowledge should be free and humans should not do same things twice)
- More time for new/other things. :nerd_face:

<p align="right">(<a href="#top">back to top</a>)</p>

### :toolbox:&nbsp; Tools and Technologies

Here is the list of tools and technologies I am using in this project.

- [talos][talos-url]
- [Flux2][flux-url]
- [Terraform][terraform-url]
- [Ubuntu](https://ubuntu.com/)
- [Cloudflare](https://www.cloudflare.com/)
- [RenovateBot](https://www.whitesourcesoftware.com/free-developer-tools/renovate/)
- [GitHub](https://github.com)

### :book:&nbsp; Overview

![terminal nodes overview][nodes-overview-url]

#### Hardware

| Device           | CPU      | OS     | OS Disk    | Data Disk              | RAM  | Purpose               |
| ---------------- | -------- | ------ | ---------- | ---------------------- | ---- | --------------------- |
| Intel NUC7i7DNHE | i7-8650U | talos  | 120 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U | talos  | 500 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U | talos  | 120 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC10I7FNH | i7-8650U | talos  | 250 GB SSD | 512GB NVMe (rook-ceph) | 32GB | worker                |

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

See the [open issues](https://github.com/tyriis/flux.k3s.cluster/issues) for a full list of proposed features (and known issues).

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

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

[terraform-url]: https://github.com/hashicorp/terraform/releases
[terraform-shield]: https://img.shields.io/badge/terraform-1.x-844fba?style=for-the-badge&logo=terraform
[talos-url]: https://www.talos.dev/
[talos-shield]: https://img.shields.io/badge/Talos-v1.2.6-fa371a?style=for-the-badge&logo=data:image/webp;base64,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
[pre-commit-url]: https://github.com/pre-commit/pre-commit
[pre-commit-shield]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white&style=for-the-badge
[renovate-dashboard-url]: https://app.renovatebot.com/dashboard#github/tyriis/flux.k3s.cluster
[renovate-shield]: https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot&style=for-the-badge
[taskfile-url]: https://taskfile.dev/
[taskfile-shield]: https://img.shields.io/badge/Taskfile-Enabled-brightgreen?logoColor=white&style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAEeElEQVR4Xu2bzU8TQRjGZ7atRQKaGAVRhBakNbYkGEPVE5IoJh403rxIgpgYwOBHPBgPxoTwDyiCelIx8SwqxhilEj9ihBCDhK8g0IIiEAqlgLi1YxZdU2DpzszOfhy2174z7/P+5nlntrtbCHT83BzqQRyAH6sc7v16yYB6JO6aCXX4Q+MFy3InR1Or0jwRrfVoCgAhZKkf7osmKrLK4dZUk2bJ7gT6UTQWw1pgCGCg0uHKxgpWGKQ6gM6Z0IPW0PgpGp1auEFVALeGehFN4SvHqAlCFQB3RwYQH03Y6sRcOABeVTjch4gHygxgCiD4c+5o09jIM9Yi4+fbPfjNVlxczIwuMwCs7I4Lj1VbKAbQOPqVD/O8FVc4yzgIwcPKbDfVBivqoAaAEDpYP9zXwrIg2rmUuIEKgNZ2xwEDOQ5UZuUR10M04PnUD/Q1PI2jR7eYJA6WlWe57uEKwAIwiFBS83DfAu6kRojDbQtZAEa0OwlgORBrAngyFmwL/JzfS5LMqLGpVq60NDOvUUqfJIDL3e3IuT7FqPVQ6ZqN8uDKTu+qeiUB7GxpWrqGv+h0UyUz2qAvs3837ob8fWQAhEEchOC8w2W0mrD0dM1Og/hfY1QAxEynM3PARpsNK7HeQYuxGOifC6+SoQiAOJvR20K0u9QiMAEgTJzEcaAiO0/vhV6WvzsyA36jxLcfmAEQM5/NygXJFl1+B/0vPopioCey2u6qOmDl5Hq1RSK7awpASLbBagPlO3I0aYveSBjwCO8Ga7wg5i0gVe0FpxvIXl8rwES66poDEBIKW9ElxhdRSgoXIWjigHjiuckp4Fj6dgXrDUBgYQ6Eo7yiOXQDICa+4HABCMkaQ3CRcCXH8qO5A2hPCxZ21/wUwF0pT0oqKNmyTTJ8ZGEOTDOyu2EBiMIuOXcB9O+nitAcnYztbngAgsAYQqBky1ZVj01djkHcdhDiDm9OJwlXFKv7Jiil3gRgOsBsAUV9TTLY3ANoboqSEKaJNTdBcxM0N0GazqEaY26C5iZI8WiMymsEg8xTwDwFDHgKCA4+0daKtLhJoUULWCBsqvP6jkt1puydSvFdAYK2JgpVFQCEoMHrS1ijLAChmgl+oejA25d+osowg9UCkD45b7uO8UotFgCxFs+bp0h49s7ywxqADXKDN7yF2M/oiACIhbNsC5YApK705BaLCoAw6f1A/9Wage5auQRy37MAcM7rTPXANKr/G1EDEAsrePcCRX4tytW55vdKAFgg/F7n9Uk/ZMBUpBiA0ragBUBjd6pjEBPkUljz+Oij6q72kyRjSAFsAjCrNt8XJMmRKJaZA+KTOF4/RlbMh6G4ACx2O6hzFTDXy3zCeBA4pwUOAFZ2V70FpBKc+fzB75+aKFrLhokAbLavK6tx7cF+9Z2mLVR1AI4bpABACGP1Xp+FpiDSMZoBEIS9R8H1pf6O+XiRKwGoaXddWkAqaXXnJ7558vvSC4YigAy7veKaq+A26QoqjdfUASvF5rY0oSNpGaDeU6ibjj9v/5xQDsUWRgAAAABJRU5ErkJggg==
[cloudflare-url]: https://dash.cloudflare.com/
[cloudflare-shield]: https://img.shields.io/badge/cloudflare-dns-F38020?logo=cloudflare&style=for-the-badge&logoColor=white
[commits-url]: https://github.com/tyriis/flux.k3s.cluster/commits/main
[commits-shield]: https://img.shields.io/github/last-commit/tyriis/flux.k3s.cluster?logo=github&style=for-the-badge
[letsencrypt-url]: https://letsencrypt.org/
[renovate-url]: https://github.com/renovatebot/renovate
[flux-url]: https://fluxcd.io/
[k8s-at-home-url]: https://k8s-at-home.com/
[nodes-overview-url]: https://imgur.com/VmJ6yE8.png
[flux-home-cluster-url]: https://github.com/tyriis/flux.home-cluster
[flux-k3s-home-url]: https://github.com/tyriis/flux.k3s.home
[flux-pi-k3s-home-url]: https://github.com/tyriis/flux.pi-k3s.home
