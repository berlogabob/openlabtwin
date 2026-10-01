---
id: 0026
date: 2026-09-26
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

The scene names each storage node after its `places.code`; the twin reads `stock` and `asset_place` and highlights those nodes. The layout lives in Godot, not in the database, so moving a shelf in the scene needs no data change.

## Decision

Place codes are the link to the Godot twin (smart storage, 2026-09-26). The scene names each storage node after its `places.code`; the twin reads `stock` and `asset_place` and highlights those nodes. The layout lives in Godot, not in the database, so moving a shelf in the scene needs no data change.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
