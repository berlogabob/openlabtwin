---
id: 0015
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Videos and photos live on the node (no cloud storage limits), and browsers block `http://` media inside an `https://` page. GitHub Pages keeps a lighter TV in the same layout.

## Decision

The showcase TV is served by the edge node, on the lab network. Videos and photos live on the node (no cloud storage limits), and browsers block `http://` media inside an `https://` page. GitHub Pages keeps a lighter TV in the same layout.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
