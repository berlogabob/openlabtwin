---
id: 0031
date: 2026-09-27
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Items, places and people are too many to scroll; the office behaves like the site's picker: type, pick, × to clear.

## Decision

One picker for every long list in the office too (`apps/office/lib/pick.dart`, a searchable `DropdownMenu` with ×). Items, places and people are too many to scroll; the office behaves like the site's picker: type, pick, × to clear.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
