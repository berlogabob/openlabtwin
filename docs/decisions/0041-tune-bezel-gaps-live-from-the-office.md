---
id: 0041
date: 2026-10-02
status: accepted
repos: [videowall]
commits: [3b43cf7]
---

## Context

Physical bezel widths need calibration while viewing the test pattern. Persist `wall_state.bezel`; convert frame millimetres to pixels by dividing by 0.264. A fixed baked-in gap cannot account for measured installation differences.

## Decision

Tune bezel gaps live from the office. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
