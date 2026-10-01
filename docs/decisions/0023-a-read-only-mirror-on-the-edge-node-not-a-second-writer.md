---
id: 0023
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Supabase stays the single source of truth. The node loads its nightly backup into local Postgres for LAN queries and a tested restore; no sync conflicts.

## Decision

A read-only mirror on the edge node, not a second writer. Supabase stays the single source of truth. The node loads its nightly backup into local Postgres for LAN queries and a tested restore; no sync conflicts.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
