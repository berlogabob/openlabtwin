---
id: 0021
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [b0e0194]
---

## Context

The wall has a Python/FFmpeg LAN server and standalone Windows use; openlabtwin is Supabase, Jaspr and Flutter. Keep rendering and Pi runtime in videowall; openlabtwin owns the office entry point and database tables. One repository couples different runtimes and makes independent open-source release harder.

## Decision

Videowall is a separate repository. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
