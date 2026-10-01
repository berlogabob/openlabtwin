---
id: 0029
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

`export.py` expands them on Lisbon wall-clock time, so 17:00 stays 17:00 across the DST change.

## Decision

Weekly repeats as `rrule` with the local UNTIL (no Z). `export.py` expands them on Lisbon wall-clock time, so 17:00 stays 17:00 across the DST change.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
