---
id: 0039
date: 2026-10-01
status: accepted
repos: [videowall]
commits: [53a086c]
---

## Context

Wall playback has wall-specific fields but follows the TV schedule model. Use `wall_slides` with TV schedule columns; link events by `activity_id` and use the same epoch-based announcement formula. Reusing TV rows would mix distinct playlists; separate event logic risks schedule disagreement.

## Decision

Wall playlist uses its own table and shared event timing. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
