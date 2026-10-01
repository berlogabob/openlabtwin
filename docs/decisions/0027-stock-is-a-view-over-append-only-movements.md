---
id: 0027
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Every change is history (needed by the thesis). Corrections are `adjust` rows.

## Decision

Stock is a view over append-only movements. Every change is history (needed by the thesis). Corrections are `adjust` rows.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
