---
id: 0020
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [b0e0194]
---

## Context

The TV media library already holds source files; tv.py removes unknown MP4 files in its managed `.tv` directory. Read sources from `~/tv-media`; write renders to `~/wall-cache`, outside `~/tv-media/.tv`. Separate media libraries duplicate files; rendering under `.tv` risks tv.py deleting outputs.

## Decision

Share TV media; keep wall renders in wall-cache. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
