---
id: 0035
date: 2026-10-01
status: accepted
repos: [videowall]
commits: [51e79ed]
---

## Context

Staff need to add wall media without opening public storage. The web client reads uploads into memory. Use private `wall-upload`, cap files at 500 MB, and allow users to delete only their own uploads. Public storage exposes staff media; unrestricted size exceeds the in-memory upload path; broad deletion exceeds ownership.

## Decision

Office uploads use a private bucket with bounded ownership. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
