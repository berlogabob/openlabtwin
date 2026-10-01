---
id: 0040
date: 2026-10-02
status: accepted
repos: [videowall]
commits: [816bdc4]
---

## Context

The thesis needs a dated, readable account while git remains the source of truth. Store daily log and decision records in openlabtwin; Hermes drafts them on the lab Windows PC with local Unsloth, review before merge, and OpenViking indexes them. A separate record system duplicates history; unreviewed generated notes can state unsupported facts.

## Decision

Keep the project record in git and index it locally. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
