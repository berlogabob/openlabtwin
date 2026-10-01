---
id: 0009
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Fast on a Raspberry Pi TV, keeps working when Supabase is down, and never holds a key.

## Decision

Public site is static, generated from the database. Fast on a Raspberry Pi TV, keeps working when Supabase is down, and never holds a key.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
