---
id: 0022
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [b0e0194]
---

## Context

The office runs as an HTTPS page while the wall server exposes plain HTTP on the LAN. Browser mixed-content rules block a direct office-to-wall request. Use `wall_state` and `wall_status`, polled by the server, following the TV node pattern. Direct HTTP from the office is blocked by the browser; proxying through another service adds an unnecessary runtime.

## Decision

Wall office control uses polled Supabase tables. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
