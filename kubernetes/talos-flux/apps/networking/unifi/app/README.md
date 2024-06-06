# unifi

## L2 Network discovery

<https://hub.docker.com/r/jacobalberty/unifi>

This just does not work. you need to ssh into the device and inform the controller manually.

## set-inform

login into your unifi device default user password: ubnt/ubnt

```console
set-inform http://${SETTING_CILIUM_UNIFI_ADDR}:8080/inform
```
