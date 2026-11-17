---
id: 0053
date: 2026-11-17
status: accepted
repos: [openlabtwin, TypstSeq]
commits: [79529da]
---

## Context

Since Wave 34, a technician can write a loan as a sentence in a TyLog day note, and it becomes a loan task in TyLog. Those tasks never reached OpenLabTwin, so the lab had two loan records that disagreed, and staff without TyLog could not see TyLog loans. Both channels also need the same rules: a tagged unit cannot be out twice. Each channel's own check (the office forms, the TyLog warning) could drift apart.

## Decision

`movements` is the only loan record. TyLog is one input channel.
- **TyLog bridge.** `TypstSeq/tool/lab_bridge.py` turns a confirmed TyLog loan task into an `issue` movement, and its "Returned" into a `return`. The movement note is `tylog:<task-id>:out` or `tylog:<task-id>:return`. A partial unique index on `movements.note` for `tylog:%` makes a repeated run harmless.
- **Double-loan rule.** The trigger `prevent_asset_double_issue` refuses an `issue` of a tagged unit whose latest movement is already an `issue`. The message names the tag, the holder and the date, so every channel shows the same refusal. Untagged stock is not affected.
- **Unknown borrower.** A borrower who is not in `people` is not created automatically. The bridge skips that loan and lists it, and staff add the person in the office.

## Alternatives considered

- TyLog as a second record, synced both ways: rejected. Two writers and conflict handling for one fact.
- A typed command parser in Postgres (`run_command`), suggested by a supervisor note: postponed. The trigger and the note key give the same guarantees for loans with far less code.
- Checking for double loans only in the clients: rejected. The office, the bridge and future channels would each need the same check.

## Consequences

- One place to read loans for the office, the TyLog "Out now" view after a sync, and the thesis metrics (channel mix by note prefix).
- A refused TyLog loan comes back to TyLog as "refused, <reason>". It is never silently dropped.
- Back-dated movements are checked against the latest movement by time, the same way `asset_place` orders them.
