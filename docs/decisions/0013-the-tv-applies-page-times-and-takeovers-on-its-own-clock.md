---
id: 0013
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

An event takes over at 17:00:00, not after the node's next minute and the TV's next reload. The node sends the day's pages with their times.

## Decision

The TV applies page times and takeovers on its own clock. An event takes over at 17:00:00, not after the node's next minute and the TV's next reload. The node sends the day's pages with their times.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
