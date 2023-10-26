# Infrastructure As Code Definitions

<details>
  <summary style="font-size:1.2em;">Table of Contents</summary>
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Ansible](#ansible)
  - [Todos](#todos)
- [Terraform](#terraform)
  - [Flux2 bootstrap and sops secret](#flux2-bootstrap-and-sops-secret)
  - [Cloudflare](#cloudflare)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
</details>

## Ansible

### Todos

- [] Add Ansible files
- [] Test ansible files against fresh installed setup
- [] Assure LVM is expanded to max size

```bash
git clone https://git.scs.carleton.ca/git/extend-lvm.git \
  && cd extend-lvm && sudo bash extend-lvm.sh /dev/sda
# need reboot afterwards
```

## Terraform

### Flux2 bootstrap and sops secret

Definitions under terraform/flux are managing the github repo initialization and configure flux2 on the given cluster to enable reconciliation against this git repository.

### Cloudflare

Configure cloudflare DNS for cert-manager
