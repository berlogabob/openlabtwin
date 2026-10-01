---
id: 0007
date: 2026-09-24
status: accepted
repos: [openlabtwin]
commits: []
---

## Context

Student ideas stay in the lab. Chat on the GPU takes seconds instead of a minute on the node's CPU; the 768-number `nomic-embed-text` vectors and thresholds stay as measured.

## Decision

Idea AI runs in the lab: chat on Unsloth Studio (the big PC's GPU), embeddings on the node's Ollama. Student ideas stay in the lab. Chat on the GPU takes seconds instead of a minute on the node's CPU; the 768-number `nomic-embed-text` vectors and thresholds stay as measured.

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
