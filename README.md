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

#### Hardware

| Device           | CPU       | OS     | OS Disk    | Data Disk              | RAM  | Purpose               |
| ---------------- | --------- | ------ | ---------- | ---------------------- | ---- | --------------------- |
| Intel NUC7i7DNHE | i7-8650U  | talos  | 120 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos  | 500 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC7i7DNHE | i7-8650U  | talos  | 120 GB SSD | 500GB NVMe (rook-ceph) | 32GB | control-plane, worker |
| Intel NUC10I7FNH | i7-10710U | talos  | 250 GB SSD |           -            | 32GB | worker                |

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
[talos-shield]: https://img.shields.io/badge/Talos-v1.2.6-fa371a?style=for-the-badge&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAW9yTlQBz6J3mgAABGRJREFUOMttlE+IXWcZxn/P+51zz52ZTCYNiQYnGkUxlVIl/glGWqJWi03SGruQLsQsWiiktCBCXUjqTmitXYjQjtiVigSRVhorGqf+wYpU07hwkagwqSSTTu/8u/eee++Zc873vS6iaYq+y3fx43ng4SduOH8acORom8tKbXfHKISfAbnH/Bgp1hq0hrMNtyHI9Ui8zrDrsMczKAWl3aMxCzZMb+MqsAreA+85cbOBXgsVe9ji+1753b6V8Cfs/wABHwvfYo6RjlPqsIbAmqG1AOsGGwlKwwfh0z6yu71mzifgruvArP5aDkC7DiZALKr1fyn6cZXhp2l76+YAwiwQq5iH3I7LeI3AIoD6Ef/qfxLmp4+T9eLR0GsPWM85+807r1CyqFK3eWJfmuA+FowMG3YTW3q3j/2Qj/zsLx/3Za0ZbHQ+7BvZ0fTbjCwefGmW8dQjju+0OvvSnff97qKHzq9i1An38NGYVa/JO+BG1s6mFOLHkO+Q+dnPfjGQetl+7/qCZ3FdN/P7jKW1ob9j7js0etbb7EnbmvlyMzs6TwxrSnaoiFPPpZBwidpT5po6lOS9oPTXdpLfFPL47dRob+qEb4z+9q6hNXM7yX72lZ+nsjgVy/xTTcVDsV+8wbC4wDD/UF12Ztph4WnQIQ3zaYbFBzXoXmB9esVG3YfSqPgkZTjVff7zL07vu4oAqo/Mg/kUVedZEp/w5HdYsIfl6ag7n3Gl7yFIsgcNfm3oBY98V+aLydIf6qnmgSxaNf2XZTKA7rkrTN77vgn4D5TsHnMdSMZVSLNyn3UiAnfCbFLa5mhZrgMudgX0w+6wqDpL/7w2m//uJ00y3BUMMFdM1goyF+54Dg6SOziOSXh0RHRloLcOu7/7ZtrGp2OrE21rr8dW51Pje1OjQWyyQWwzYhtE3R2kphjE1t7ZtuF829rrddKJOoaZwe5brwGX3/4BruSVKnXurxXuat2e2aSzUnlxS+N2qUX9GlRJmhibtbhUY7dsxXyl8fBM4+HIWH7/hShd3nUr9pgfYqqZvXcLPVahX2wFX2iJeydo/0h2bmQ2rpAqiVLFeILOTQj7y2DzjbSwBS/Wbqd2m9/7QCPsYTs/N7RwspRdbLBHN1MYbpoO9s22bwR7eQN83Yy+jCYl3zR7ecPCXN/s4KqF4ch4tDQujoyT3yo0l81k9FdaewL55ehaGloRplJzl5Eum/zVltxEwlzEDMtlr0a0nNw+NzA7vSf6UsAfdGPvTsq+bvTh6T23AXp/ULNoxBe+sPbnkz/Z9fECOCOX5zE79p75cf33lc7TIh5t4Q7gH/ctv/K/+npy/jB9M3qmIz3lO1ZVPLew63Z6ylhVzqoyrgbxx5UZ1pQ//4aKm3oqjvTV4an5w2/q68aES11ne2NXHH7UifZKFFRm4AI5LYGChOF/SvIfB/nyOMCO+k3GWyp/fd/t6Nqvm0RVptwdCtCZaw62Y8LrWY9qjalWVA7pqUu/uc74N6DdUmr/G0k5AAAAAElFTkSuQmCC
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
[flux-home-cluster-url]: https://github.com/tyriis/flux.home-cluster
[flux-k3s-home-url]: https://github.com/tyriis/flux.k3s.home
[flux-pi-k3s-home-url]: https://github.com/tyriis/flux.pi-k3s.home
