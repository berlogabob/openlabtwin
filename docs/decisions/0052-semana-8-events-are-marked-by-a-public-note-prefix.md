---
id: 0052
date: 2026-10-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

IADE's Semana 8 (26-30 Oct 2026) has 49 events. The TV must highlight them, and those at TechLab | GameStudio must show in the day column.

## Decision

`scripts/semana8.py` loads the programme as approved `event` activities. Their `public_note` starts with `Semana 8`; no schema change. `tv.py` turns such an activity into a carousel page tagged "Semana 8", today only and first in the loop; the TV colours them in the day column. Lab events carry the Tech Lab place, the others a free-text room. Remove them after the week: `DELETE activities WHERE public_note LIKE 'Semana 8%'`.

## Alternatives considered

- A new `tag` column: a migration for a one-week need.
- One takeover page per day: hides the normal loop all day.

## Consequences

A prefix is a convention: an edit in the office that drops it removes the highlight. Reuse needs the constant `WEEK` in `tv.py` changed.
