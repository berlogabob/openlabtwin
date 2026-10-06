---
id: 0043
date: 2026-10-02
status: accepted
repos: [videowall]
commits: []
---

## Context

All 25 Pis, 25 monitors and the network gear run from one switched 8-way strip (agreed with building operations for testing). One USB charger port keeps at most 2 Pis out of under-voltage; more gave 0x50000 flags and power-dip reboots. Switching everything at once gives one large inrush peak.

## Decision

One switched head strip per row and one for the network: NET 3-way (TP-Link 8, TP-Link 24, Wi-Fi bridge charger); rows 1–3 on 3-way heads with 4-ways (row 3 with the 6-way without switch); rows 4–5 on the 5-way and 6-way switched strips, whose cables are short. A row is 5 monitors + 3 chargers (2+2+1) = 8 sockets. Power-up: MAIN, NET, then rows 1–5 about 10 s apart. LAN: TP-Link 8 ports 1–5 row 1, port 6 to TP-Link 24 port 23, port 8 the Wi-Fi bridge; TP-Link 24 ports 1–5 row 2, 6–10 row 3, 11–15 row 4, 16–20 row 5.

## Alternatives considered

- Use every strip in the kit (layout proposed earlier): more joints and levels for no benefit.
- One 8-way switched strip per row: two levels, fewer joints; needs a purchase, not possible now.
- More Pis per charger to save sockets: measured under-voltage and reboots.

## Consequences

Each row can be switched off on its own and rows start one after another. Under-voltage still appears on some rows (A3, B3 on 2026-10-03/06), so charger ports or cables there need replacing. One switched 3-way stays spare for the PC in the other room.
