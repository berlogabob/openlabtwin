---
id: 0046
date: 2026-10-07
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The public schedule opens with the Tech Lab room preselected. Its smart lists then offered only professors teaching in that room, so users could not combine a room with a professor from elsewhere without first removing the room chip.

## Decision

Picking a value in any other field while the room is still exactly the default clears the room (any room). A room the user chose is kept.

## Consequences

A professor pick on the bare URL searches all rooms. Pick a room afterwards to narrow.
