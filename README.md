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

[![k3s][k3s-shield]][k3s-url]
[![terraform][terraform-shield]][terraform-url]
[![cloudflare][cloudflare-shield]][cloudflare-url]
[![pre-commit][pre-commit-shield]][pre-commit-url]
[![renovate][renovate-shield]][renovate-url]
[![commits][commits-shield]][commits-url]

<!-- PROJECT LOGO -->
<!--<br />
<div align="center">
  <img src="https://cncf-branding.netlify.app/img/projects/flux/horizontal/color/flux-horizontal-color.svg" alt="Logo" width="200" heigh="103">
</div>-->
<br />

# Kubernetes GitOps Cluster

- :briefcase: managed with Flux2 and Terraform
- :robot: updated by RenovateBot

<br />
<!-- TABLE OF CONTENTS -->
<details>
  <summary style="font-size:1.2em;">Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#toolbox-tools-and-technologies">:toolbox:&nbsp;Tools and Technologies</a></li>
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
    <li><a href="#detective-troubleshooting">:detective:&nbsp; Troubleshooting</a></li>
  </ol>
</details>

<br />

<!-- ABOUT THE PROJECT -->

## About The Project

This is a private project. I want to share it with you. I started my journey with kuberntes and GitOps a few years ago.

Goals:

- Automate my home and home infrastructure.
- Learn new things everyday.
- Challenge myself.
- Share my findings and work with you cause knowledge should be free and humans should not do same things twice.
- More time for new/other things. :nerd_face:

<p align="right">(<a href="#top">back to top</a>)</p>

### :toolbox:&nbsp; Tools and Technologies

Here is the list of tools and technologies I am using in this project.

- [k3s](https://k3s.io/)
- [Flux2](https://fluxcd.io/)
- [Terraform](https://www.terraform.io/)
- [Ubuntu](https://ubuntu.com/)
- [Cloudflare](https://www.cloudflare.com/)
- [RenovateBot](https://www.whitesourcesoftware.com/free-developer-tools/renovate/)
- [GitHub](https://github.com)

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

See the [open issues](https://github.com/tyriis/flux.k3s.home/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- TROUBLESHOOTING -->

## :detective:&nbsp; Troubleshooting

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
[k3s-url]: https://k3s.io/
[k3s-shield]: https://img.shields.io/badge/k3s-v1.23.3-ffc61c?style=for-the-badge&logo=kubernetes&logoColor=white
[pre-commit-url]: https://github.com/pre-commit/pre-commit
[pre-commit-shield]: https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white&style=for-the-badge
[renovate-url]: https://app.renovatebot.com/dashboard
[renovate-shield]: https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot&style=for-the-badge
[cloudflare-url]: https://dash.cloudflare.com/
[cloudflare-shield]: https://img.shields.io/badge/cloudflare-dns-F38020?logo=cloudflare&style=for-the-badge&logoColor=white
[commits-url]: https://github.com/tyriis/flux.k3s.cluster/commits/main
[commits-shield]: https://img.shields.io/github/last-commit/tyriis/flux.k3s.cluster?logo=github&style=for-the-badge
