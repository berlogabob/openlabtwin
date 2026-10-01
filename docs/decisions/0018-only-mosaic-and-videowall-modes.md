---
id: 0018
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [b0e0194]
---

## Context

Mosaic assigns a media item per screen; Videowall splits one composition across screens. Keep two modes; treating “same media” as Mosaic avoids a third mode. A third mode duplicates Mosaic behavior without adding a distinct playback model.

## Decision

Only Mosaic and Videowall modes. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.

Addendum 2026-10-02: zones (regions of the wall with their own content) were considered for the operator panel and rejected by the owner; one mode applies to the whole wall.
