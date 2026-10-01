---
id: 0008
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Jaspr outputs real HTML, which is light on the TV. Flutter reuses the UNIDCOM RIMS patterns for a signed-in app.

## Decision

Jaspr for the site, Flutter for the office. Jaspr outputs real HTML, which is light on the TV. Flutter reuses the UNIDCOM RIMS patterns for a signed-in app.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
