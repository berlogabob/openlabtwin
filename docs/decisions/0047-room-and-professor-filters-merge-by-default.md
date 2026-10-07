---
id: 0047
date: 2026-10-07
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Planning a booking needs the busy times of a lab, a second lab and a professor together. Filters ANDed across fields, so "3D Lab + Andre Sabino" showed only their intersection, and each list narrowed by the other.

## Decision

A **Room / professor** switch: Any (default) ORs the chosen rooms and professors; All keeps the AND (`match=all`). Other fields always AND. In Any mode room and professor lists don't narrow each other.

## Consequences

Saved favourites with both a room and a professor now merge unless re-saved with All. Complements 0046.
