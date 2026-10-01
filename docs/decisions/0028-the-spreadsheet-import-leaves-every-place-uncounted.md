---
id: 0028
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The previous team's list isn't trusted. Needs attention shows each stocked place as never counted until someone counts it; the counts replace the spreadsheet's numbers as `adjust` rows.

## Decision

The spreadsheet import leaves every place uncounted. The previous team's list isn't trusted. Needs attention shows each stocked place as never counted until someone counts it; the counts replace the spreadsheet's numbers as `adjust` rows.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
