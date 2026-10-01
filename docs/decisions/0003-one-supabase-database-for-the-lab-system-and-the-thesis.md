---
id: 0003
date: 2026-09-23
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

A single record of rooms, bookings and stock. The thesis measures the same data the lab uses.

## Decision

One Supabase database for the lab system and the thesis. A single record of rooms, bookings and stock. The thesis measures the same data the lab uses.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
