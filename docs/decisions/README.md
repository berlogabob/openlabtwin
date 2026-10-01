# Decision records

Each decision uses YAML front matter (`id`, `date`, `status`, `repos`, `commits`), then Context, Decision, Alternatives considered (with reasons), and Consequences.
Dates are decision dates; records are numbered chronologically. Reversals add a record and mark the earlier record superseded.

| id | date | title | status |
|---|---|---|---|
| [0001](0001-bookings-reach-the-site-by-periodic-export-not-a-database-webhook.md) | 2026-09-23 | Bookings reach the site by periodic export, not a database webhook | accepted |
| [0002](0002-links-on-the-site-resolve-from-the-base-href-the-site-root.md) | 2026-09-23 | Links on the site resolve from the `<base href>` (the site root) | accepted |
| [0003](0003-one-supabase-database-for-the-lab-system-and-the-thesis.md) | 2026-09-23 | One Supabase database for the lab system and the thesis | accepted |
| [0004](0004-skills-matched-phrase-by-phrase-not-as-whole-lists.md) | 2026-09-23 | Skills matched phrase by phrase, not as whole lists | accepted |
| [0005](0005-a-tv-page-can-be-linked-to-a-schedule-activity-tv-slides-activity-id.md) | 2026-09-24 | A TV page can be linked to a schedule activity (`tv_slides.activity_id`) | accepted |
| [0006](0006-all-database-work-over-https-postgrest-management-api.md) | 2026-09-24 | All database work over HTTPS (PostgREST, Management API) | accepted |
| [0007](0007-idea-ai-runs-in-the-lab-chat-on-unsloth-studio-the-big-pc-s-gpu-embeddings-on-the-node-s-ollama.md) | 2026-09-24 | Idea AI runs in the lab: chat on Unsloth Studio (the big PC's GPU), embeddings on the node's Ollama | accepted |
| [0008](0008-jaspr-for-the-site-flutter-for-the-office.md) | 2026-09-24 | Jaspr for the site, Flutter for the office | accepted |
| [0009](0009-public-site-is-static-generated-from-the-database.md) | 2026-09-24 | Public site is static, generated from the database | accepted |
| [0010](0010-several-tvs-stay-in-sync-by-the-clock-with-no-server.md) | 2026-09-24 | Several TVs stay in sync by the clock, with no server | accepted |
| [0011](0011-staff-accounts-made-by-an-admin-sign-ups-disabled.md) | 2026-09-24 | Staff accounts made by an admin; sign-ups disabled | accepted |
| [0012](0012-student-records-kept-identifiable-indefinitely-with-no-consent-tick-user-2026-09-24.md) | 2026-09-24 | Student records kept identifiable, indefinitely, with no consent tick (user, 2026-09-24) | accepted |
| [0013](0013-the-tv-applies-page-times-and-takeovers-on-its-own-clock.md) | 2026-09-24 | The TV applies page times and takeovers on its own clock | accepted |
| [0014](0014-the-node-makes-lighter-video-copies-the-tv-picks-one-by-dropped-frames.md) | 2026-09-24 | The node makes lighter video copies; the TV picks one by dropped frames | accepted |
| [0015](0015-the-showcase-tv-is-served-by-the-edge-node-on-the-lab-network.md) | 2026-09-24 | The showcase TV is served by the edge node, on the lab network | accepted |
| [0016](0016-urllib-instead-of-the-supabase-python-package.md) | 2026-09-24 | `urllib` instead of the `supabase` Python package | accepted |
| [0017](0017-grid-dimensions-stay-on-the-server.md) | 2026-09-25 | Grid dimensions stay on the server | accepted |
| [0018](0018-only-mosaic-and-videowall-modes.md) | 2026-09-25 | Only Mosaic and Videowall modes | accepted |
| [0019](0019-server-renders-with-ffmpeg-pis-play-with-mpv.md) | 2026-09-25 | Server renders with FFmpeg; Pis play with mpv | accepted |
| [0020](0020-share-tv-media-keep-wall-renders-in-wall-cache.md) | 2026-09-25 | Share TV media; keep wall renders in wall-cache | accepted |
| [0021](0021-videowall-is-a-separate-repository.md) | 2026-09-25 | Videowall is a separate repository | accepted |
| [0022](0022-wall-office-control-uses-polled-supabase-tables.md) | 2026-09-25 | Wall office control uses polled Supabase tables | accepted |
| [0023](0023-a-read-only-mirror-on-the-edge-node-not-a-second-writer.md) | 2026-09-26 | A read-only mirror on the edge node, not a second writer | accepted |
| [0024](0024-clash-checks-warn-never-block.md) | 2026-09-26 | Clash checks warn, never block | accepted |
| [0025](0025-kits-and-movements-pick-tagged-units-automatically.md) | 2026-09-26 | Kits and movements pick tagged units automatically | accepted |
| [0026](0026-place-codes-are-the-link-to-the-godot-twin-smart-storage-2026-09-26.md) | 2026-09-26 | Place codes are the link to the Godot twin (smart storage, 2026-09-26) | accepted |
| [0027](0027-stock-is-a-view-over-append-only-movements.md) | 2026-09-26 | Stock is a view over append-only movements | accepted |
| [0028](0028-the-spreadsheet-import-leaves-every-place-uncounted.md) | 2026-09-26 | The spreadsheet import leaves every place uncounted | accepted |
| [0029](0029-weekly-repeats-as-rrule-with-the-local-until-no-z.md) | 2026-09-26 | Weekly repeats as `rrule` with the local UNTIL (no Z) | accepted |
| [0030](0030-one-picker-for-every-list-on-the-public-site-apps-site-lib-pick-dart.md) | 2026-09-27 | One picker for every list on the public site (`apps/site/lib/pick.dart`) | accepted |
| [0031](0031-one-picker-for-every-long-list-in-the-office-too-apps-office-lib-pick-dart-a-searchable-dropdownmenu-with.md) | 2026-09-27 | One picker for every long list in the office too (`apps/office/lib/pick.dart`, a searchable `DropdownMenu` with ×) | accepted |
| [0032](0032-the-student-number-is-required-on-every-public-form-user-2026-09-27.md) | 2026-09-27 | The student number is required on every public form (user, 2026-09-27) | accepted |
| [0033](0033-wall-pis-use-wired-ethernet-only.md) | 2026-09-30 | Wall Pis use wired Ethernet only | accepted |
| [0034](0034-delegate-coding-to-codex-cli-and-local-models.md) | 2026-10-01 | Delegate coding to Codex CLI and local models | accepted |
| [0035](0035-office-uploads-use-a-private-bucket-with-bounded-ownership.md) | 2026-10-01 | Office uploads use a private bucket with bounded ownership | accepted |
| [0036](0036-stagger-reboot-all-by-30-seconds.md) | 2026-10-01 | Stagger reboot-all by 30 seconds | accepted |
| [0037](0037-start-the-client-from-cron-until-stable.md) | 2026-10-01 | Start the client from cron until stable | accepted |
| [0038](0038-synchronize-playback-with-server-timestamps-and-measured-seek-latency.md) | 2026-10-01 | Synchronize playback with server timestamps and measured seek latency | accepted |
| [0039](0039-wall-playlist-uses-its-own-table-and-shared-event-timing.md) | 2026-10-01 | Wall playlist uses its own table and shared event timing | accepted |
| [0040](0040-keep-the-project-record-in-git-and-index-it-locally.md) | 2026-10-02 | Keep the project record in git and index it locally | accepted |
| [0041](0041-tune-bezel-gaps-live-from-the-office.md) | 2026-10-02 | Tune bezel gaps live from the office | accepted |
