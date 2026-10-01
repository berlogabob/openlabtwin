---
id: 0038
date: 2026-10-01
status: accepted
repos: [videowall]
commits: [7c84f45]
---

## Context

Screens must start and seek to a common point despite clock and seek differences. Use absolute server timestamps, chrony on Pis, client drift correction, and learn seek latency per Pi. Relative delays accumulate drift; fixed seek compensation ignores hardware differences. A Pi 3 seek takes about 2 s; measured drift was -13..-33 ms.

## Decision

Synchronize playback with server timestamps and measured seek latency. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
