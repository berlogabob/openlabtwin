---
id: 0034
date: 2026-10-01
status: superseded by 0049 (Codex part)
repos: [videowall]
commits: [95079bf]
---

## Context

The owner prefers to reserve Claude tokens for review and integration. Use Codex CLI (gpt-6-luna) and local models for implementation; Claude prepares briefs, reviews hot paths and merges. Using Claude for routine coding spends the limited review budget on implementation.

## Decision

Delegate coding to Codex CLI and local models. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
