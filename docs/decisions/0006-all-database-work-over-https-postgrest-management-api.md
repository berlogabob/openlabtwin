---
id: 0006
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The IADE network blocks outgoing Postgres ports 5432 and 6543, and Docker is not used. See [OPERATIONS → Network](OPERATIONS.md#network).

## Decision

All database work over HTTPS (PostgREST, Management API). The IADE network blocks outgoing Postgres ports 5432 and 6543, and Docker is not used. See [OPERATIONS → Network](OPERATIONS.md#network).

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
