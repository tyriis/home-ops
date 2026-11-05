---
status: accepted
date: 2026-11-05
decision-makers: [tyriis]
---

# Pin 2.4 GHz Wi-Fi to channels 6 + 11 to keep the ZigBee band clear

## Context and Problem Statement

Wi-Fi and ZigBee share the 2.4 GHz band, and their channel numbers are unrelated scales:
Wi-Fi channel N sits at 2412 + 5 × (N − 1) MHz, ZigBee channel N at 2405 + 5 × (N − 11) MHz.
Identical numbers therefore mean unrelated frequencies, and the overlap map is:

| Wi-Fi ch | Occupies (MHz) | Covers ZigBee ch |
| -------- | -------------- | ---------------- |
| 1        | 2402–2422      | 11–14            |
| 6        | 2427–2447      | 15–20            |
| 11       | 2452–2472      | 20–24            |

Wi-Fi sideband lobes extend a few MHz beyond the 20 MHz block, so adjacent ZigBee channels are
not safe neighbours either. When both systems overlap, the narrow (2 MHz) ZigBee channels lose —
typically as silent packet loss and device flapping across ~100 sensors, not as a visible alarm.

The ZigBee network runs on **channel 11 (2405 MHz)** — the zigbee2mqtt default, not an explicit
override. The Wi-Fi deployment (UniFi, managed outside this repository) runs its 2.4 GHz radios
on **6** (livingroom, ~32 clients) and **11** (office). Channel 1 is deliberately unused: it
would land directly on top of the ZigBee network.

Nothing recorded this pairing, and both UniFi radios are on auto-channel. Controller-driven
channel optimisation has been observed moving radios unsolicited. A future hop of the
livingroom radio to 1 (or to any channel ≥1) covering 2405 MHz would degrade the whole ZigBee
fleet with no trace in Git history.

## Considered Options

- Wi-Fi on 1 + 6, ZigBee high (25/26) — rejected: many ZigBee devices do not support
  channel 26, and 25/26 sit inside Wi-Fi 11's block if 11 is ever reintroduced.
- Wi-Fi on 1 + 11 or 6 + 11 variants — 6 + 11 chosen because 6 carries the AP pair farthest
  from ZigBee 11 with no constraint on future ZigBee growth upward from 11.
- Move ZigBee instead (e.g. to 25) — rejected: ~100 devices must rejoin on a channel change,
  a far more disruptive action than a Wi-Fi channel choice, and 25 has weak device support.
- Leave both on auto-channel — rejected: auto-optimisation has no awareness of the ZigBee
  network and will happily hop onto 1.

## Decision Outcome

Chosen option: **Wi-Fi 2.4 GHz pinned to 6 and 11 only; ZigBee stays on channel 11.**

Constraints that follow:

- Do not enable Wi-Fi channel 1 on any AP — it directly covers ZigBee 11–14.
- Pin both 2.4 GHz radios in the UniFi console (auto-channel has already moved radios once).
  UniFi state lives outside this repo, so this document is the only record of the invariant.
- Any future Wi-Fi channel change must preserve a clear 2400–2422 MHz window first.
- If ZigBee ever needs to move (co-tenant ZigBee/Thread networks), retune from the ZigBee
  side using the overlap table above, and re-verify after Wi-Fi throughput tests.

Verification of the live state: UniFi controller radio status (`unifi_get_device_radio` via the
unifi-mcp) and zigbee2mqtt channel from the retained `zigbee2mqtt/bridge/info` MQTT message.
