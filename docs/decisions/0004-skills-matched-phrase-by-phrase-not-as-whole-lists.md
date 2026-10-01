---
id: 0004
date: 2026-09-23
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Measured: whole lists blur ("electronics, soil sensors" against "electronics, esp32" scored 0.55); phrase against phrase gives 1.0 for the same skill and about 0.4 for unrelated ones.

## Decision

Skills matched phrase by phrase, not as whole lists. Measured: whole lists blur ("electronics, soil sensors" against "electronics, esp32" scored 0.55); phrase against phrase gives 1.0 for the same skill and about 0.4 for unrelated ones.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
