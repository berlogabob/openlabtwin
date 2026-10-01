---
id: 0002
date: 2026-09-23
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

So a page links `kit/` or fetches `data/all.json`, never `../…`, whatever its own path.

## Decision

Links on the site resolve from the `<base href>` (the site root). So a page links `kit/` or fetches `data/all.json`, never `../…`, whatever its own path.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
