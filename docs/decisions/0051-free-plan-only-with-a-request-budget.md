---
id: 0051
date: 2026-10-21
status: accepted
repos: [openlabtwin, videowall]
commits: []
---

## Context

Egress hit 11.66 GB against the 5.5 GB free limit. The org was put under service restrictions and the project paused; restoring it required Pro, which the owner cannot buy. Cause: about 264,000 REST requests in 7 days from always-on pollers (wall server every 2 s, `tv.py` every minute, `ideas_ai` and `archive_ocr` every 15 min, `publish.sh` every 10 min, open office tabs every 5 s). Storage was empty.

## Decision

Free plan only. Supabase holds data people edit; the node and GitHub Pages serve everything derived from it. Nothing polls Supabase faster than people edit. Budget: under 2,000 REST requests a day. Intervals: wall server 10 s (heartbeat 30 s), `tv.py` 5 min, `publish.sh` 30 min, `ideas_ai` and `archive_ocr` hourly. A new script or loop states its requests per day before it ships.

The project moved to a new free org and project (`ukelqvkanfimiafnomex`) from the 2026-10-12 backup with `scripts/restore.py`.

## Alternatives considered

- Upgrade to Pro. Rejected: not affordable.
- Wait for the billing cycle. Rejected: the restriction kept the project paused with no date.

## Consequences

Office commands reach the wall up to 10 s late. A restriction can strike again: keep the nightly backup and `restore.py` working, and check usage monthly.
