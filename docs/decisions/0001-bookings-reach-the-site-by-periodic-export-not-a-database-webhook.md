---
id: 0001
date: 2026-09-23
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

No GitHub token stored in Supabase. GitHub's own 10-minute cron never fired, so the lab edge node runs the export ([edge-node.md](edge-node.md)).

## Decision

Bookings reach the site by periodic export, not a database webhook. No GitHub token stored in Supabase. GitHub's own 10-minute cron never fired, so the lab edge node runs the export ([edge-node.md](edge-node.md)).

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
