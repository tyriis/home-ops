# flux.k3s.cluster | k3s based gitops cluster managed by flux2

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
