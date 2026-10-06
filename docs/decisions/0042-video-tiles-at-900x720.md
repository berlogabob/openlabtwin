---
id: 0042
date: 2026-10-06
status: accepted
repos: [videowall]
commits: [79e1ec0]
---

## Context

Mounted against the monitor backs, the Pi 3B+ boards decoding 1280×1024 H.264 tiles at 4 Mb/s ran at 60–67 °C, at or above the 60 °C soft limit, for days (throttled flag 0x80008). Throttled CPUs drop frames.

## Decision

Videowall video tiles are encoded at 900×720, 2.5 Mb/s; mpv scales them to the 1280×1024 screen on the GPU. Mosaic video tiles use the TV's 720p copy (`~/tv-media/.tv/`) at 2.5 Mb/s. Stills stay at full 1280×1024.

## Alternatives considered

- Keep 1280×1024 and add cooling only: cooling is not built yet; the wall has to run now.
- Hardware decode (`--hwdec=v4l2m2m-copy`): measured 155 dropped frames in 20 s against 2 with software decode.
- Lower frame rate: visible on motion; pixel count is the larger cost.

## Consequences

Measured 2026-10-06 on 12–15 Pis: 44–57 °C, drift −28 to −2 ms, 0 dropped frames. Video is softer at screen distance; stills are unaffected. Render keys include the tile size, so old 1280×1024 renders are not reused.
