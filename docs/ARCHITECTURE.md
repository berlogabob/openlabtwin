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
| `apps/site` | Jaspr static site: schedule page with multi-select filters, lab TV page | its own `data/all.json` |
| `apps/office` | Flutter web app for staff: bookings, equipment, inventory | Supabase directly, as the signed-in staff member |
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
- **audit_log:** a trigger records every write to the tables above, except `lessons`, which the scraper rewrites every 6 hours; git history of `all.json` covers them.

Thesis link: timetable + bookings with headcount and equipment give *known demand*, and `movements` gives *actual use*. The milestone 5 forecast is a query over these tables and needs no new schema.

## Privacy: three layers, and why all three

This follows UNIDCOM RIMS, which learned the hard way that row-level security has no column dimension.

1. **Grants.** The `anon` role has no privileges on any table or view (`20260923120100_access.sql`, including default privileges for future tables). The anon key ships in the office's JavaScript, so this layer is what makes that safe.
2. **RLS.** Every table allows reads and writes only when `is_staff()` is true, meaning a `people` row with `is_staff` linked to the signed-in `auth_user_id`. `movements` can't be updated or deleted by staff, `lessons` can't be written by staff, and `audit_log` is read-only.
3. **Export allowlist.** `export.py` runs with the service key, which bypasses RLS. So it selects explicit columns only and fails if a record carries a key outside `KEYS`. Emails, `purpose`, equipment lists, stock and loans never reach the public files.

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
| Weekly repeats as `rrule` with the local UNTIL (no Z) | `export.py` expands them on Lisbon wall-clock time, so 17:00 stays 17:00 across the DST change. |

## Status

| Milestone | State |
|---|---|
| 1 Core database, timetable sync, export | live |
| 2 Public site, multi-select filters, lab TV, lab.ics | live |
| 3 Back office: bookings, approval, equipment, clash warnings | live |
| 4 Inventory: movements, stock, loans, kit issue/return, stationary clashes | live |
| Edge node for 10-minute publishing | planned, machine arrives 2026-09-24 |
| 5 Thesis layer: demand forecast, Godot view | not started; scope depends on the thesis topic change |

Deferred on purpose: serial-numbered assets and RFID/QR tagging, procurement, professor and student sign-in, consultation self-booking, and local-first sync.
