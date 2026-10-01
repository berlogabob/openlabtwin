---
id: 0010
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Each screen computes the page from the time (the loop runs from the epoch), picks ideas from a seed shared by the loop number, reloads at second 20 of each minute (after the node's rebuild), and keeps a video within 1.5 s of the clock. Needs correct clocks on the TV computers.

## Decision

Several TVs stay in sync by the clock, with no server. Each screen computes the page from the time (the loop runs from the epoch), picks ideas from a seed shared by the loop number, reloads at second 20 of each minute (after the node's rebuild), and keeps a video within 1.5 s of the clock. Needs correct clocks on the TV computers.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
