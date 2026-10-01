---
id: 0014
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

A slow TV computer (Pi 3) can't play 10 Mbit/s 1080p; the copies also make iPhone HEVC videos playable.

## Decision

The node makes lighter video copies; the TV picks one by dropped frames. A slow TV computer (Pi 3) can't play 10 Mbit/s 1080p; the copies also make iPhone HEVC videos playable.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
