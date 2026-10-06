---
id: 0044
date: 2026-10-06
status: accepted
repos: [openlabtwin, videowall]
commits: []
---

## Context

The office Wall screen opened with a static picture and held no way to upload in Videowall mode, while the real controls lived on the wall server's page at `http://192.168.1.131:8080/`, which an https page cannot open. The office page itself rendered blank when `www.gstatic.com` (CanvasKit) was blocked.

## Decision

The office Wall screen is the only control UI: mode, file, fit, Show now, Files/Upload in both modes, Gaps with the Test pattern and preview, announcements. The server's LAN page stays as a local fallback in the site's colours. The office build self-hosts CanvasKit (`--no-web-resources-cdn`). Files named `announcement*` are not in the media picker or in "all files"; they play only from their own "Put on screen" button.

## Consequences

The preview URL is renewed only when the picture changes or after 45 s. The LAN page address is no longer shown in the office.
