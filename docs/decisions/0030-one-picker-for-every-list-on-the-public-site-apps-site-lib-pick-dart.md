---
id: 0030
date: 2026-09-27
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The schedule filters' behaviour everywhere: picked values as chips with ×, a search field whose dropdown lists the known values (a `<datalist>`), Enter for free text where allowed. Used by the schedule filters, the equipment request (courses from the timetable, the lab's items with a quantity each) and the idea form's skills.

## Decision

One picker for every list on the public site (`apps/site/lib/pick.dart`). The schedule filters' behaviour everywhere: picked values as chips with ×, a search field whose dropdown lists the known values (a `<datalist>`), Enter for free text where allowed. Used by the schedule filters, the equipment request (courses from the timetable, the lab's items with a quantity each) and the idea form's skills.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
