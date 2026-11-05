# Channel Plan (2.4 GHz)

Wi-Fi and ZigBee share the 2.4 GHz band, and their channel numbers are unrelated scales:
Wi-Fi channel N sits at 2412 + 5 × (N − 1) MHz, ZigBee channel N at 2405 + 5 × (N − 11) MHz.
Identical numbers mean unrelated frequencies — Wi-Fi 11 (2462 MHz) and ZigBee 11 (2405 MHz)
are 57 MHz apart.

The overlap map:

| Wi-Fi ch | Occupies (MHz) | Covers ZigBee ch |
| -------- | -------------- | ---------------- |
| 1        | 2402–2422      | 11–14            |
| 6        | 2427–2447      | 15–20            |
| 11       | 2452–2472      | 20–24            |

Wi-Fi sideband lobes extend a few MHz beyond the 20 MHz block, so channels adjacent to an
active Wi-Fi channel are not safe for ZigBee either. Overlapping systems do not fail loudly:
the narrow 2 MHz ZigBee channels lose as silent packet loss and device flapping.

## Current allocation

| Network                | Channel | Frequency | Owner of state         |
| ---------------------- | ------- | --------- | ---------------------- |
| Wi-Fi 2.4 (livingroom) | 6       | 2427–2447 | UniFi controller       |
| Wi-Fi 2.4 (office)     | 11      | 2452–2472 | UniFi controller       |
| ZigBee (all devices)   | 11      | 2405      | zigbee2mqtt PVC config |

## Rules

1. **Never enable Wi-Fi channel 1.** It lands directly on the ZigBee network (ZigBee 11–14).
2. **Keep 2400–2422 MHz clear of Wi-Fi** — any future 2.4 GHz channel change must preserve that window before taking effect.
3. **Pin both 2.4 GHz radios** in the UniFi console. Do not leave them on auto-channel: UniFi's auto-optimisation has moved radios unsolicited and has no awareness of the ZigBee network.
4. **Move ZigBee last.** A ZigBee channel change forces ~100 devices to rejoin; a Wi-Fi channel change affects only reassociation. Retune from the ZigBee side only if co-tenant ZigBee/Thread networks encroach, using the overlap table above.

Rationale and rejected options: ADR
[0023-wifi-zigbee-channel-plan](../../../../decisions/0023-wifi-zigbee-channel-plan.md)
(`docs/decisions/`).
