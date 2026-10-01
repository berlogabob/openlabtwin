---
id: 0025
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

An issue takes the tags on that shelf, a return the tags the person holds, untagged units make up the rest, and staff see the tags before anything is written. So stock and each tag's place never disagree, without making staff pick tags one by one. A tag not found at a count stays in stock, marked missing: reversible, and it shows in Needs attention.

## Decision

Kits and movements pick tagged units automatically. An issue takes the tags on that shelf, a return the tags the person holds, untagged units make up the rest, and staff see the tags before anything is written. So stock and each tag's place never disagree, without making staff pick tags one by one. A tag not found at a count stays in stock, marked missing: reversible, and it shows in Needs attention.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
