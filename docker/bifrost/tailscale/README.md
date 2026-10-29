# bifrost tailscale node

Status: dormant (2026-10-28). The deploy entry was removed from
`docker/.doco-cd.bifrost.yaml` — the Lightwhale image cannot boot the
prerequisites reliably: persistent `/etc` becomes visible only at
`S11persistence` inside a forward-only `rcS`, the netfilter kernel is
cut-down, and a clean reboot hung and needed a hard reset during
verification. The truenas SCALE app keeps the router role.

Runtime validation passed fully: registration, peering, subnet-routing
rules, and offsite transit all worked while the node ran.

## To re-adopt on a future host

1. Add the entry back to `docker/.doco-cd.<host>.yaml` with a proper host-init hook (early, persistent, before the docker daemon).
2. Mint a fresh authkey and re-encrypt `sops.env` with that host's age key. The previous `sops.env` was deleted together with its key.
3. See the repo history of PR #11450 for the validated compose shape.
