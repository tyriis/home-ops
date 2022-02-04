# Infrastructure As Code Definitions

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

Definitions under terraform/flux are managing the github repo initialization and configure flux2 on the given cluster to enable reconcilation against this git repository.

### Cloudflare

Configure cloudflare DNS for cert-manager
