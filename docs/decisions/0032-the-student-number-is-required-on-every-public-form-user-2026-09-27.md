---
id: 0032
date: 2026-09-27
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

It is the lab's local ID for a person, the key of their history; staff give their staff number. Enforced once, in `check_contact()`.

## Decision

The student number is required on every public form (user, 2026-09-27). It is the lab's local ID for a person, the key of their history; staff give their staff number. Enforced once, in `check_contact()`.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
