---
status: accepted
date: 2026-09-14
decision-makers: [tyriis]
---

# Reserve 192.168.100.90-99 for DHCP on the UniFi controller

## Context and Problem Statement

The `192.168.100.0/24` network carries both statically-addressed infrastructure and
dynamically-addressed clients, but nothing in this repository recorded where the boundary between
the two sits. Allocations were only discoverable by grepping the repo:

- `.1` gateway/DNS, `.2` NAS, `.10` bifrost host
- `.30`, `.31` utility cluster (control-plane VIP `.30`)
- `.40`–`.49` utility Cilium `LoadBalancerIPPool` (`l2-pool`)
- `.100`–`.103` main cluster (control-plane VIP `.100`, nodes `.101`–`.103`)
- `.200`–`.250` main Cilium `LoadBalancerIPPool`; services already drawn from it: `.200`
  Envoy gateway, `.201` mosquitto, `.202`/`.212` minecraft, `.204` syncthing, `.214`
  home-assistant, `.215` plex

Without a reserved DHCP scope, the UniFi controller can hand a client an address that a Cilium
pool or a future node later claims, producing an intermittent ARP/L2 conflict that is hard to
diagnose.

## Considered Options

- `192.168.100.90`–`.99` (10 addresses) — top of the free gap below the main cluster
- `192.168.100.50`–`.99` (50 addresses) — the whole gap between the utility pool and `.100`
- `192.168.100.104`–`.199` (96 addresses) — the gap above the existing main-cluster nodes
- No reservation, rely on UniFi's default scope

## Decision Outcome

Chosen option: **`192.168.100.90`–`.99`**, configured as the DHCP scope on the UniFi controller,
because it is the smallest block that satisfies current client demand while staying clear of both
Cilium pools and of the direction in which the clusters grow.

Reservation rules that follow from this:

- `.90`–`.99` is the only DHCP range on this network; everything outside it is static and must not
  be handed out automatically.
- `.50`–`.89` stays unallocated and is the first place to extend the DHCP scope if 10 addresses run
  out.
- `.104`–`.199` stays unallocated and is reserved for main-cluster node growth beyond `.103`.
- The main Cilium pool (`.200`–`.250`) may only be extended downwards after a corresponding DHCP
  range shrink; upwards it is limited to `.251`–`.254`.

### Consequences

- Good, because the static/dynamic boundary is now written down, so a future pool or node change is
  checked against it instead of guessed.
- Good, because `.90`–`.99` is adjacent to nothing that grows: utility pool grows up from `.40`,
  main cluster grows up from `.100`, and both stop well short.
- Good, because keeping the scope small leaves `.50`–`.89` as headroom rather than burning it on
  addresses that are unlikely to be used.
- Neutral, because the scope is configured in the UniFi controller, which is outside this
  repository — this ADR records the intent, it does not enforce it.
- Bad, because 10 addresses are consumed by any set of clients with phones, laptops and IoT gear;
  exhaustion is plausible and would require a deliberate extension.
- Bad, because `.99` sits directly below the control-plane VIP `.100` — a mis-typed scope end
  (`.100` or higher) would conflict with the main cluster's API endpoint.
