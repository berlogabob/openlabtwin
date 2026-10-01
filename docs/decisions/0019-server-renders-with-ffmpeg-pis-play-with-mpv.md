---
id: 0019
date: 2026-09-25
status: accepted
repos: [videowall]
commits: [6face79]
---

## Context

Rendering belongs on the server; the Pis have limited compute and need identical tiles. Use FFmpeg only on the server, with no Pillow; clients download and play through mpv using software decoding. Pillow duplicates image processing; hardware decode dropped 155 frames versus 2 with software decode.

## Decision

Server renders with FFmpeg; Pis play with mpv. 

## Alternatives considered

- Alternative: do not adopt this choice. Rejected because it does not meet the stated reason above.
- Alternative: add a separate mechanism. Rejected because the existing project path covers the requirement with less operational state.

## Consequences

The implementation and operating guidance follow this choice. Revisit this record if the stated constraints change.
