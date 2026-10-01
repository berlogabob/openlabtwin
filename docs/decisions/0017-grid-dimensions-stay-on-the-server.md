---
id: 0017
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [b0e0194]
---

## Context

The server knows the full canvas and tile placement. Configure rows and columns only on the server; each Pi receives its grid code such as A1 and hostname wall-a1. Duplicating the grid configuration on each Pi creates inconsistent deployment state.

## Decision

Grid dimensions stay on the server. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
