---
id: 0033
date: 2026-09-30
status: accepted
repos: [videowall]
commits: [6da0df9]
---

## Context

Two addresses made wall-XX.local alternate and SSH time out. Disable Wi-Fi and use cable networking for wall Pis. Keeping Wi-Fi as fallback preserved the address conflict and unreliable remote access.

## Decision

Wall Pis use wired Ethernet only. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
