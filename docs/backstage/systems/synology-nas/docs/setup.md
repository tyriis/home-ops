<!-- markdownlint-disable MD033 -->
<!-- markdownlint-disable MD046 -->
<!-- markdownlint-disable MD013 -->

# Step by Step Setup

## Initial User and email MFA

create user and add email MFA

## Storage Pool

Create a new storage pool RAID 1 (to tolerate drive failures), BTRFS

## Setup Domain

    Synology DSM -> Control Panel -> Login Portal -> Domain

## Setup DNS entry

In DNS setup a record to point the domain to the synology ip

## Enable SSH Access

    Synology DSM -> Control Panel -> Terminal & SNMP
      Enable SSH service -> Apply

## Enable ACME DNS-01 Challenge

see ACME DNS-01 Challenge document

```bash file=/usr/local/etc/synology-letsencrypt/env
DOMAINS=(--domains "synology.techtales.io" --domains "*.synology.techtales.io")
EMAIL="admin@techtales.io"
DNS_PROVIDER="cloudflare"
export CLOUDFLARE_DNS_API_TOKEN=my_key
```

test:

```terminal
/usr/local/bin/synology-letsencrypt.sh
```

## Setup Scheduled Task for cert rotation and renewal

    Synology DSM -> Control Panel -> Task Scheduler
      Create -> Scheduled Task -> User-defined script
        General
          Task: cert-renew
          User: root
        Task Settings
          User-defined script: /bin/bash /usr/local/bin/synology-letsencrypt.sh
        OK
        OK
        Confirm with password

## Enable Certificate

    Synology DSM -> Control Panel -> Security
      Certificate -> Settings -> Configure
        Switch all services to the new certificate
        OK -> Yes

## Enable 2-Factor Authentication (2FA)

    Synology DSM -> User Menu -> Personal
      Security -> 2-Factor Authentication
        Hardware security key -> enter password -> Usb key / passkey
        OK -> Yes
        Insert and tap security key
        Scan recovery with Authenticator App
        Add 2nd Hardware Key for backup
        Apply

## Setup Container Manager

    Synology DSM -> Package Center -> Search -> container manager
      Install

## Install doco-cd

get the [compose.yaml](https://github.com/tyriis/home-ops/blob/main/docker/deploy/doco-cd/compose.yaml)

Synology has no git client installed.

```bash
curl https://raw.githubusercontent.com/tyriis/home-ops/refs/heads/main/docker/deploy/doco-cd/compose.yaml -O
```

Synology does not support config.content.
comment file location in and file content out

```bash
sed -i '10s/^[[:space:]]*# //; 11,14s/^/# /' compose.yaml
```

create the doco-cd config folder as root

```bash
mkdir -p /etc/doco-cd
```

next create the poll config as root

```bash
cat <<EOF > /etc/doco-cd/poll-config.yml
- url: https://github.com/tyriis/home-ops.git
  target: synology
  interval: 180
EOF
```

create the file `/etc/doco-cd/age-keys.txt` with the content of `infra/synology/doco-cd` secret as root

```bash
sudo vim /etc/doco-cd/age-keys.txt
```

create the file `/etc/doco-cd/webhook_secret` with the content of `infra/synology/doco-cd` secret as root

```bash
sudo vim /etc/doco-cd/webhook_secret
```

make them readable by root only

```bash
sudo chmod 600 /etc/doco-cd/age-keys.txt && sudo chmod 600 /etc/doco-cd/webhook_secret
```

## Fix TUN/TAP not available on a Synology NAS (required for tailscale)

Link on [memoryleak.dev](https://memoryleak.dev/post/fix-tun-tap-not-available-on-a-synology-nas/)

In Synology DSM ssh shell run as root:

```bash
insmod /lib/modules/tun.ko
```

Check if tun.ko module works

```bash
cat /dev/net/tun
```

should return `File descriptor in bad state`

In order to persist the setting

```bash
cat <<EOF > /usr/local/bin/tun.sh
#!/bin/sh -e

insmod /lib/modules/tun.ko
EOF
```

```bash
chmod a+x /usr/local/bin/tun.sh
```

    Synology DSM -> Control Panel -> Task Scheduler
      Create -> Triggered Task -> User-defined script
        General
          Task: tun-module-load
          User: root
          Event: Boot-up
        Task Settings
          User-defined script:
            /bin/bash /usr/local/bin/tun.sh
        OK
        OK
        Confirm with password

## start doco-cd

in the doco cd compose folder

```bash
docker compose up -d
```

## Setup DNS to point to tailscale net

    Unifi -> Settings
      Policy Engine -> Policy Table
        Create New Policy -> DNS
          Type: Host (A)
          Domain Name: synology.techtales.io
          IP: <ip of the tailscale node>

## Add DNS server to synology

    Synology DSM -> Control Panel -> Network
      General
        Manually configure DNS server -> Check
          Prefered DNS server: 192.168.1.1 (tailscale connected unifi)
          Alternative DNS server: the one that has been ina as Prefered before

Name resolution with techtales services should work now

```bash
curl https://home.techtales.io
```

## setup synology proxy

    Synology DSM -> Control Panel -> Login Portal
      DSM -> Domain
        Customized domain: synology.techtales.io
        Save
        OK

Should be available under [synology.techtales.io](https://synology.techtales.io)

## use letsencrypt certificate

    Synology DSM -> Security -> Certificate
      synology.techtales.io -> Right Click -> Edit
        Set as default certificate: true

    Settings -> Configure
      System default: synology.techtales.io
      synology.techtales.io: synology.techtales.io
      OK
      Yes

## Setup Synology Nginx proxy for minio

    Synology DSM -> Control Panel -> Login Portal
      Advanced -> Reverse Proxy
        Create
          General
            Reverse Proxy Name: minio
            Source:
              Protocol: HTTPS
              Hostnamne: minio.synology.techtales.io
              Port: 443
              Enable HSTS: true
            Destination:
              Protocol: HTTP
              Hostname: localhost
              Port: 9001
          Custom Header
            Create -> WebSocket
          Save

        Create
          General
            Reverse Proxy Name: s3
            Source:
              Protocol: HTTPS
              Hostnamne: s3.synology.techtales.io
              Port: 443
              Enable HSTS: true
            Destination:
              Protocol: HTTP
              Hostname: localhost
              Port: 9000
          Save
