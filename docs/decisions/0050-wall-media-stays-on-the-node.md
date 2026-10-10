---
id: 0050
date: 2026-10-10
status: accepted
repos: [openlabtwin, videowall]
commits: []
---

## Context

Supabase Storage hit its quota. The `wall-upload` bucket (office uploads, copied to the node, never deleted) was the main source.

## Decision

Video wall media never goes through Supabase. Files are added on the node: the wall server's LAN page (Upload) or the shared folder. The office upload and the node's download loop are removed, and the `wall-upload` bucket is dropped. Only the small `wall-preview` image stays. The GitHub Pages TV gets light copies only: the 480p video copy and 1280 px photo copies, at most 15 MB per file.

## Alternatives considered

- Delete each object after the node fetches it. Rejected: still sends every video through the quota, and the owner wants no media in Supabase.

## Consequences

Staff off the lab network add files through the shared folder or Tailscale, not the office. `archive` (loan sheet scans) is unchanged and still counts against the quota.
