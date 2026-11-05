# Home Network

The home site network: UniFi LAN/VLAN fabric, Wi-Fi radios, and the ZigBee mesh that carries
roughly 100 sensors. Management of this domain sits outside GitOps — the UniFi controller holds
its own state, and the ZigBee coordinator config lives on a PVC — which makes these pages the
system of record for the constraints that cross the boundary.

## Scope

- Wi-Fi 2.4 GHz / 5 GHz channel planning (UniFi: UDM SE gateway, U6+ livingroom, U6+ office)
- ZigBee network (zigbee2mqtt on the main cluster, slaesh.cc2652rb coordinator)
- Site-wide invariants that no single system's config implies on its own

## Pages

- [Channel Plan (2.4 GHz)](channel-plan.md) — which channels each radio may occupy and why.

## Verify live state

| What                          | Command                                                        |
| ----------------------------- | -------------------------------------------------------------- |
| Wi-Fi radio channels (per AP) | unifi-mcp `unifi_get_device_radio` (MAC of each AP)            |
| ZigBee channel + device map   | retained MQTT `zigbee2mqtt/bridge/info` on `mqtt.techtales.io` |
