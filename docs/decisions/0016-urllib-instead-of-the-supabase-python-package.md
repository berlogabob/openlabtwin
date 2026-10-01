---
id: 0016
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

About seven REST calls didn't justify ~55 packages; a live export was byte-identical afterwards.

## Decision

`urllib` instead of the `supabase` Python package. About seven REST calls didn't justify ~55 packages; a live export was byte-identical afterwards.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
