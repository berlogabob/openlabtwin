---
id: 0045
date: 2026-10-06
status: accepted
repos: [videowall]
commits: []
---

## Context

Mosaic video tiles were still 1280×1024 (the heaviest decode on a Pi 3B+), a tile's loop `period` came from the source file (389.583 s against 389.600 s for the tile), the client changed speed at 0.04 s of drift every second, and the bezel gaps on the running server were 0.

## Decision

Mosaic video tiles are 900×720 like Videowall ([0042](0042-video-tiles-at-900x720.md)); video tiles use x264 `-tune fastdecode`; `period` is read from the rendered tile; the client's speed-nudge deadband is 0.10 s; server gap defaults are 132 px (columns) and 151 px (rows), from frames of 17.5 + 17.5 mm and 25.5 + 14.5 mm at 0.264 mm per pixel. `RENDER_VERSION` 2 re-renders every tile once.

## Consequences

The measured frames are approximate: re-tune on the Test pattern. A gap saved in `wall_state.bezel` overrides the defaults.
