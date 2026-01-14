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
<div align="center">

<!-- [![taskfile][taskfile-shield]][taskfile-url]
[![pre-commit][pre-commit-shield]][pre-commit-url] -->

[![talos][talos-shield]][talos-url]
[![kubernetes][kubernetes-shield]][kubernetes-url]
[![Flux][flux-shield]][flux-url]
<br />

[![renovate][renovate-shield]][renovate-dashboard-url]
[![Status-Page][gatus-shield]][gatus-url]
[![commits][commits-shield]][commits-url]

<!-- [![cloudflare][cloudflare-shield]][cloudflare-url] -->
<!-- PROJECT LOGO -->
<br />
  <img src="https://storage.googleapis.com/techtales-public-images/groot-home-ops.png" alt="Logo" width="250" height="250" style="display:block;">
<br />
<br />

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fcluster_alert_count&style=flat-square&label=Alerts)](https://github.com/kashalls/kromgo)

</div>

# GitOps my home infra

- 💼 managed with [Flux2][flux-url]
- 🤖 updated by [RenovateBot][renovate-url]
- 🔐 secured by [Let's Encrypt][letsencrypt-url] and [Cloudflare Tunnel][cloudflared-url]

<details>
  <summary style="font-size:1.2em;">Table of Contents</summary>
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Statistics](#statistics)
- [About The Project](#about-the-project)
  - [🧰 Tools and Technologies](#%F0%9F%A7%B0-tools-and-technologies)
  - [📖 Overview](#-overview)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [Configure SOPS (optional)](#configure-sops-optional)
  - [Configure kubectl](#configure-kubectl)
- [Roadmap](#roadmap)
- [🕵️ Troubleshooting](#%EF%B8%8F-troubleshooting)
  - [Stuck HelmRelease](#stuck-helmrelease)
- [Quality](#quality)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
</details>

<!-- ABOUT THE PROJECT -->

## Statistics

![Alt](https://repobeats.axiom.co/api/embed/bcccc4d3f022bf36870bd9bcc2397eecaea695c7.svg "Repobeats analytics image")

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

| Tool                              | Role                                                            |
| --------------------------------- | --------------------------------------------------------------- |
| [talos][talos-url]                | Linux designed for Kubernetes – secure, immutable, and minimal. |
| [Flux2][flux-url]                 | Kubernetes GitOps engine                                        |
| [Cloudflare][cloudflare-homepage] | DNS and tunnels to allow external traffic                       |
| [RenovateBot][renovate-url]       | Automated dependency updates.                                   |
| [GitHub][github-url]              | Code Hosting and job runnner                                    |
| [Backstage][backstage-url]        | Documentation with backstage developer portal                   |

### 📖 Overview

#### Hardware

| Device                 | CPU       | OS    | OS Disk   | Data Disk              | RAM  | Purpose    |
| ---------------------- | --------- | ----- | --------- | ---------------------- | ---- | ---------- |
| MS-01                  | i9-13900H | Talos | 1 TB NVMe | 500GB NVMe (rook-ceph) | 96GB | Kubernetes |
| MS-01                  | i9-13900H | Talos | 1 TB NVMe | 500GB NVMe (rook-ceph) | 96GB | Kubernetes |
| MS-01                  | i9-13900H | Talos | 1 TB NVMe | 500GB NVMe (rook-ceph) | 96GB | Kubernetes |
| ASUS NUC 14 Essentials | N250      | Talos | 1 TB NVMe | 2x 500GB SSD           | 16GB | NAS        |
| AOSTAR WTR Pro         | N100      | Talos | 1 TB NVMe | 2x 8 TB HDD            | 32GB | NAS        |
| UniFi UDM SE           | -         | -     | 128GB SSD | -                      | -    | Router     |
| UniFi USW Aggregation  | -         | -     | -         | -                      | -    | Switch     |

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- GETTING STARTED -->

## Getting Started

### Prerequisites

- mozilla sops
- age
- talhelper

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->

## Usage

### Configure SOPS (optional)

Provide key in path defined in `.envrc`.

### Configure kubectl

Just run

```shell
task talos:config
task talos:kubeconfig
```

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
[gatus-url]: https://status.techtales.io

<!-- Badges -->

[renovate-shield]: https://img.shields.io/badge/renovate-enabled-brightgreen?style=for-the-badge&logo=renovate
[renovate-url]: https://www.whitesourcesoftware.com/free-developer-tools/renovate/
[commits-shield]: https://img.shields.io/github/last-commit/tyriis/home-ops?style=for-the-badge&logo=github
[commits-url]: https://github.com/tyriis/home-ops/commits/main
[talos-shield]: https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fkromgo.techtales.io%2Fquery%3Fformat%3Dendpoint%26metric%3Dtalos_version&query=%24.message&style=for-the-badge&logo=talos&label=talos&color=%23ff7300&cacheSeconds=600
[talos-url]: https://www.talos.dev/
[kubernetes-shield]: https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fkromgo.techtales.io%2Fquery%3Fformat%3Dendpoint%26metric%3Dkubernetes_version&query=%24.message&style=for-the-badge&logo=kubernetes&label=kubernetes&color=%23326CE5&cacheSeconds=600
[kubernetes-url]: https://kubernetes.io/releases/
[cloudflared-url]: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
[flux-shield]: https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.techtales.io%2Fflux_version&style=for-the-badge&logo=flux&logoColor=326CE5&color=326CE5&label=flux&cacheSeconds=600
[gatus-shield]: https://img.shields.io/uptimerobot/status/m800769967-13f5c929f419ccdd73096f8a?color=brightgreeen&label=Status&style=for-the-badge&logo=data:image/svg%2bxml;base64,CjxzdmcgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWw6c3BhY2U9InByZXNlcnZlIiB2aWV3Qm94PSIwIDAgNTEyIDUxMiI+PHBhdGggZD0iTTE5Mi4xIDM3M2MtNjQuNS0zNS4zLTg4LjItMTE2LjMtNTIuOC0xODAuOCAxMi4zLTIyLjQgMzAuOC00MC45IDUzLjMtNTMuMSA2LjktMy44IDE0LjItNi45IDIxLjctOS40IDU0LjEtMTcuMSA5MS02Ny4xIDkxLjYtMTIzLjhDMzAyLjUuMiAyOTEuMS4yIDI1Ni4yLjJjLTUxLjggMC01Mi41IDEtNTAuMyAxOC40IDYuMSA0Ni4zLTUzLjcgNzEuMy04Mi40IDM0LjItMTEuMS0xNC40LTEyLTE0LjQtNDkuNSAyMy43LTM1LjUgMzUuOS0zNi4xIDM1LjgtMjEuNSA0Ny4xQzY5IDEzNi4zIDc1IDE1OC42IDY3IDE3Ny45Yy04LjMgMTkuMy0yOC42IDMwLjYtNDkuNCAyNy42QzAgMjAzLjQgMCAyMDQgMCAyNThjLjUgNDkuMSAwIDUwLjIgMTguOCA0OC4xIDI1LjItMyA0OC4xIDE1IDUxLjEgNDAuMiAxLjcgMTQuNS0zLjYgMjktMTQuMiAzOS0xNy4xIDE2LjEtMTYuMiAxNC45IDE2LjIgNDguNCAzMSAzMi4xIDM2LjEgMzguNCA0Ni41IDI5LjlsNzUuNS03NS41YzMuOC0zLjQgNC4xLTkuMy43LTEzLjEtLjctLjktMS42LTEuNS0yLjUtMiIgc3R5bGU9ImZpbGw6IzNjYWQ0YiIvPjxwYXRoIGQ9Ik00ODcuMyAyMDYuM2MtMjUuNS0uMi00Ni4xLTIxLjEtNDUuOC00Ni43LjEtMTMuMiA1LjktMjUuNyAxNS44LTM0LjQgMTYuMy0xNC4zIDE2LjEtMTMuNS0yMC4zLTQ5LjktMjQuNi0yNC42LTMyLjYtMzIuOC0zOS4yLTMwLjhMMzE4IDEyNC40Yy0zLjcgMy43LTMuNyA5LjYgMCAxMy4zLjYuNiAxLjMgMS4yIDIuMSAxLjYgNjQuNSAzNS40IDg4LjEgMTE2LjMgNTIuNyAxODAuOC0xMi4zIDIyLjQtMzAuOCA0MC44LTUzLjMgNTMtOS4zIDQuOS0xOSA4LjctMjkuMiAxMS40LTQ4LjcgMTMtODQgNTQuOS04NCAxMDUuNHY3LjJjLjkgMTQuNSA2LjggMTMuOCA0NiAxNC40IDUzLjIuOCA1MS45IDIgNTMuNS0yNi42IDEuNS0yNS41IDIzLjQtNDUgNDguOS00My41IDExLjguNyAyMi45IDUuOSAzMSAxNC41IDE3LjEgMTggMTMuNiAxNy43IDQ5LjgtMTcuOSAzNy40LTM2LjkgMzkuMS0zNS43IDIxLTUyLjEtMTguOS0xNy4yLTIwLjMtNDYuNC0zLjEtNjUuMyA5LjYtMTAuNSAyMy41LTE2LjEgMzcuNy0xNSAyMSAxLjUgMjAgLjMgMjAuNy00Ni4xLjgtNTIuNCAxLjYtNTMtMjQuNS01My4yIiBzdHlsZT0iZmlsbDojMDE3NDAwIi8+PHBhdGggZD0iTTIzNC41IDMzNi43aDQ1LjZjMi40IDAgNC40LTEuOSA0LjQtNC4zdi00NC43YzAtMi40IDEuOS00LjMgNC4zLTQuM2g0NC44YzIuNCAwIDQuNC0yIDQuNC00LjR2LTQ2YzAtMi40LTItNC4zLTQuNC00LjNoLTQ0LjRjLTIuNCAwLTQuNC0xLjktNC40LTQuM3YtNDQuOGMwLTIuNC0xLjktNC40LTQuMy00LjRoLTQ1LjdjLTIuNCAwLTQuNCAxLjktNC40IDQuM3Y0NC44YzAgMi40LTEuOSA0LjQtNC4zIDQuNEgxODFjLTIuNCAwLTQuNCAxLjktNC40IDQuM3Y0NmMwIDIuNCAyIDQuNCA0LjQgNC40aDQ0LjdjMi40IDAgNC40IDEuOSA0LjQgNC4zdjQ0LjljLjEgMi40IDIuMSA0LjIgNC40IDQuMSIgc3R5bGU9ImZpbGw6IzFlOTAyNSIvPjwvc3ZnPg==
