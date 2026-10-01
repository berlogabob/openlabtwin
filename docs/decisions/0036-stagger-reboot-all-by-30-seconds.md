---
id: 0036
date: 2026-10-01
status: accepted
repos: [videowall]
commits: [082d3c1]
---

## Context

The Pis share a USB charger and simultaneous boot risks peak current. Reboot screens in order with 30 seconds between them; expose power flags in the office. Simultaneous reboot creates avoidable peak load; an unstaggered command gives operators no power feedback.

## Decision

Stagger reboot-all by 30 seconds. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
