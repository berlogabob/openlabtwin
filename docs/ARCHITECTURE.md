# Architecture

How OpenLabTwin fits together, and why. For day-to-day procedures see [OPERATIONS.md](OPERATIONS.md).

## The parts

```
IADE timetable site ──scrape──► scripts/timetable.py ──┐
                                                       ▼
Staff ──email link──► apps/office (Flutter web) ──► Supabase (Postgres + RLS)  ◄── single source of truth
                                                       │
                              scripts/export.py ◄──────┘   (service key; explicit columns; key allowlist)
                                     │
                     apps/site/web/data/all.json + calendar/lab.ics   (committed to git)
                                     │
                 GitHub Actions: build apps/site (Jaspr) + apps/office → GitHub Pages
                                     │
                    schedule page · lab TV · lab.ics · office (all static files)
```

| Part | What it is | Talks to |
|---|---|---|
| Supabase project `openlabtwin` (ref `huqecytswaswkswofrqd`, eu-central-1) | Postgres with row-level security, email sign-in | everything |
| `scripts/timetable.py` | Scrapes every IADE class page and upserts `lessons` from this Monday on. Older lessons stay as history. | IADE site, Supabase REST |
| `scripts/export.py` | Writes the public `all.json` and `lab.ics` from lessons and **approved** activities | Supabase REST |
| `apps/site` | Jaspr static site: schedule page with multi-select filters, Book me, idea hub, and a TV page in the showcase layout (QR codes and events only) | its own `data/all.json`; Supabase public functions |
| `apps/tv` | Showcase TV page (plain HTML/JS, no build), served by the edge node's nginx: schedule column plus slide carousel. It applies page times and takeovers on its own clock, and picks a video copy (480p/720p/1080p) by the device and its dropped frames | `tv.json` and `all.json` on the node |
| `scripts/tv.py` | Runs on the edge node every minute: probes the shared TV folder (only changed files), syncs `tv_media`, writes the day's public `tv.json` (explicit columns, key allowlist, ideas as AI title and summary only), writes the `tv_status` heartbeat, and makes the lighter video copies | Supabase REST, local files, ffmpeg |
| `apps/office` | Flutter web app for staff: bookings, equipment, inventory, TV slides | Supabase directly, as the signed-in staff member |
| `sync.yml` | Scrape → export → commit data → build both apps → deploy to Pages | GitHub, Supabase |
| `scripts/publish.sh` | Runs on the lab edge node: export (and scrape) and push when the data changed | GitHub, Supabase |

## Data model

The tables are in `supabase/migrations/20260923120000_core_schema.sql`.

- **places:** rooms and storage (`tier` fast or long). `iade_name` ties a room to the timetable's room name, and `public` decides whether it is ever exported.
- **items** (consumable, portable, stationary), and **movements**, which is append-only: receive, move, issue, return, consume, adjust.
- **stock** (view): the sum of movements per item and place. It is never stored.
- **on_loan** (view): issued minus returned, per item and person.
- **people** (staff, professors, students, external), and **organizations** (clubs, courses, projects).
- **activities:** bookings and events in one table, with a `layer` column. Weekly repeats are stored as an `rrule` plus `exdates`. The status runs requested → approved / rejected / cancelled / done.
- **activity_items:** the equipment to prepare for an activity, including booked stationary machines.
- **lessons:** the scraped timetable.
- **ideas / idea_matches / idea_skills:** the idea hub. Each idea belongs to a student (`people`), has the AI's English title, summary, keywords and summary vector, and a private token. `idea_skills` holds one vector per "brings" or "needs" phrase. `idea_matches` pairs two ideas as similar or complementary, with each side's connect flag.
- **consultation_hours:** weekly bookable hours per staff member and room. Book me turns them into free slots.
- **tv_media / tv_slides / tv_status:** the TV showcase. `tv_media` is the edge node's list of files in its shared TV folder (written by the node only). `tv_slides` is every page the TV plays, in order: media, bio, QR, text, plus the automatic `events` and `ideas` pages; each has seconds (empty: a video plays to its end), dates, times of day, full screen and takeover. `media_name` is a plain file name, so a page survives its file being briefly missing. `tv_status` is the node's one-row heartbeat (last build, what plays now, last error), read by the office.
- **audit_log:** a trigger records every write to the tables above, except `lessons`, `tv_media` and `tv_status`, which scripts rewrite constantly (lessons every 6 hours); git history of `all.json` covers them.

Thesis link: timetable + bookings with headcount and equipment give *known demand*, and `movements` gives *actual use*. The milestone 5 forecast is a query over these tables and needs no new schema.

## Privacy: layers, and why all of them

This follows UNIDCOM RIMS, which learned the hard way that row-level security has no column dimension.

1. **Grants.** The `anon` role has no privileges on any table or view (`20260923120100_access.sql`, including default privileges for future tables). The anon key ships in the office's JavaScript, so this layer is what makes that safe.
2. **RLS.** Every table allows reads and writes only when `is_staff()` is true, meaning a `people` row with `is_staff` linked to the signed-in `auth_user_id`. `movements` can't be updated or deleted by staff, `lessons`, `tv_media` and `tv_status` can't be written by staff, and `audit_log` is read-only.
3. **Public functions.** The only exception to layer 1: `anon` may execute `free_slots`, `request_consultation` and `consultation_status` (Book me), plus `submit_idea`, `idea_status` and `idea_connect` (idea hub). All share the `check_contact` / `file_student` helpers. They run as `security definer`, so they bypass RLS, and each one validates its own input and returns only what the student may see.
4. **Export allowlist.** `export.py` runs with the service key, which bypasses RLS. So it selects explicit columns only and fails if a record carries a key outside `KEYS`. Emails, `purpose`, equipment lists, stock and loans never reach the public files.

## Decisions and why

| Decision | Why |
|---|---|
| One Supabase database for the lab system and the thesis | A single record of rooms, bookings and stock. The thesis measures the same data the lab uses. |
| Public site is static, generated from the database | Fast on a Raspberry Pi TV, keeps working when Supabase is down, and never holds a key. |
| Jaspr for the site, Flutter for the office | Jaspr outputs real HTML, which is light on the TV. Flutter reuses the UNIDCOM RIMS patterns for a signed-in app. |
| All database work over HTTPS (PostgREST, Management API) | The IADE network blocks outgoing Postgres ports 5432 and 6543, and Docker is not used. See [OPERATIONS → Network](OPERATIONS.md#network). |
| `urllib` instead of the `supabase` Python package | About seven REST calls didn't justify ~55 packages; a live export was byte-identical afterwards. |
| Staff accounts made by an admin; sign-ups disabled | Anyone could otherwise create an auth user. Staff are few. |
| Stock is a view over append-only movements | Every change is history (needed by the thesis). Corrections are `adjust` rows. |
| Clash checks warn, never block | Staff decide; real life has exceptions. |
| Bookings reach the site by periodic export, not a database webhook | No GitHub token stored in Supabase. GitHub's own 10-minute cron never fired, so the lab edge node runs the export ([edge-node.md](edge-node.md)). |
| Student records kept identifiable, indefinitely, with no consent tick (user, 2026-09-24) | Each student's history is a logbook for monthly reports, faster help, the lab's ethnographic research and course design. Students consented through their IADE agreements; forms show a one-line notice. Staff-only access (RLS). |
| Idea AI runs in the lab: chat on Unsloth Studio (the big PC's GPU), embeddings on the node's Ollama | Student ideas stay in the lab. Chat on the GPU takes seconds instead of a minute on the node's CPU; the 768-number `nomic-embed-text` vectors and thresholds stay as measured. |
| The showcase TV is served by the edge node, on the lab network | Videos and photos live on the node (no cloud storage limits), and browsers block `http://` media inside an `https://` page. GitHub Pages keeps a lighter TV in the same layout. |
| The TV applies page times and takeovers on its own clock | An event takes over at 17:00:00, not after the node's next minute and the TV's next reload. The node sends the day's pages with their times. |
| A TV page can be linked to a schedule activity (`tv_slides.activity_id`) | The event is entered once, in the schedule; its page plays in its slot and follows it when it moves or is cancelled (`link_events` in `tv.py`). |
| Several TVs stay in sync by the clock, with no server | Each screen computes the page from the time (the loop runs from the epoch), picks ideas from a seed shared by the loop number, reloads at second 20 of each minute (after the node's rebuild), and keeps a video within 1.5 s of the clock. Needs correct clocks on the TV computers. |
| The node makes lighter video copies; the TV picks one by dropped frames | A slow TV computer (Pi 3) can't play 10 Mbit/s 1080p; the copies also make iPhone HEVC videos playable. |
| Skills matched phrase by phrase, not as whole lists | Measured: whole lists blur ("electronics, soil sensors" against "electronics, esp32" scored 0.55); phrase against phrase gives 1.0 for the same skill and about 0.4 for unrelated ones. |
| Weekly repeats as `rrule` with the local UNTIL (no Z) | `export.py` expands them on Lisbon wall-clock time, so 17:00 stays 17:00 across the DST change. |

## Status

| Milestone | State |
|---|---|
| 1 Core database, timetable sync, export | live |
| 2 Public site, multi-select filters, lab TV, lab.ics | live |
| 3 Back office: bookings, approval, equipment, clash warnings | live |
| 4 Inventory: movements, stock, loans, kit issue/return, stationary clashes | live |
| Book me: consultation requests by QR, private status link, consultation hours, student history | live |
| Idea hub: QR form, local AI normalising and matching, connect by mutual consent, office idea bank | live |
| Edge node (TechLAB-01): 10-minute publishing, 6-hourly scrape, 15-minute idea AI (chat on Unsloth Studio, embeddings local), nightly backup | live since 2026-09-24 |
| TV showcase: node-served TV (schedule column plus carousel), office TV list (every page, event takeovers, warnings, heartbeat), lighter video copies, shared folder | live since 2026-09-25; the TV computer (Pi) setup is next ([ROADMAP](ROADMAP.md)) |
| Tailscale: Mac, node and Studio PC on one tailnet (Studio and the node reachable from home) | live since 2026-09-25 |
| 5 Thesis layer: demand forecast, Godot view | not started; scope depends on the thesis topic change |

What's next is in [ROADMAP.md](ROADMAP.md). Deferred on purpose: serial-numbered assets and RFID/QR tagging, procurement, professor and student sign-in, consultation self-booking, and local-first sync.
