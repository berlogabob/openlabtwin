---
id: 0037
date: 2026-10-01
status: accepted
repos: [videowall]
commits: [32e4941]
---

## Context

The Pi client must recover at boot and remain supervised. Use cron `@reboot` to launch the supervised loop; retain the owner rule against systemd until stable. Systemd adds service configuration before the runtime has stabilized.

## Decision

Start the client from cron until stable. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
