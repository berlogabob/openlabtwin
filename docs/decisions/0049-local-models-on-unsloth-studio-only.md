---
id: 0049
date: 2026-10-09
status: accepted
repos: [openlabtwin, videowall]
commits: []
---

## Context

Decision 0034 delegated coding to Codex CLI and local models. The owner now wants Claude Code spent on review and live changes only, and implementation done by local models on Unsloth Studio, in small tracked tasks.

## Decision

Implementation tasks in [docs/PLAN-screens.md](../PLAN-screens.md) run on Unsloth Studio (Qwen3-Coder-30B through pi, or Studio's API directly), one task per run, gated by the task's test. Claude writes specs, reviews diffs and does anything that touches the live database or the node. Codex is no longer used; this supersedes the Codex part of 0034.

## Alternatives considered

- Keep Codex for hot paths. Rejected: the owner wants one tool chain, and Studio is on the lab network.
- Claude writes everything. Rejected: it spends the review budget on routine coding.

## Consequences

Tasks must be small and name their files and test, because the local model has a smaller context. Claude reviews each diff before merge.
