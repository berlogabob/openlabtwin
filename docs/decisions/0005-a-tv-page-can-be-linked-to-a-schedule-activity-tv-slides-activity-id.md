---
id: 0005
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The event is entered once, in the schedule; its page plays in its slot and follows it when it moves or is cancelled (`link_events` in `tv.py`).

## Decision

A TV page can be linked to a schedule activity (`tv_slides.activity_id`). The event is entered once, in the schedule; its page plays in its slot and follows it when it moves or is cancelled (`link_events` in `tv.py`).

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
