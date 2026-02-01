# Cloudflared

in order to be able to manage the tunnel on the cluster side, it is required to create the credentials.json manually

1st login to cloudflare and allow tunnel scope

```terminal
cloudflared login
```

2md create the tunnel with name `home-vpc`

```terminal
cloudflared login && cloudflared tunnel create home-vpc
```

> will result in something like

```console
Tunnel credentials written to ~/.cloudflared/08cbb673-9e41-4b16-99b2-6cc4b5e6755c.json. cloudflared chose this file based on where your origin certificate was found. Keep this file secret. To revoke these credentials, delete the tunnel.
```

in the last step we load transfer the secert to our secret store

tunnels are listed in the cloudflare dashboard( assure it has an (i) in front of the name saying the tunnel is locally managed)
