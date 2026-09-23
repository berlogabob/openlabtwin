# OpenLabTwin core: design

Date: 2026-09-23. Status: draft for review.

## Why

The IADE lab schedule site (`iade-lab-schedule`) started as a scraper and a static page. The lab now needs:

- bookings with a requester, a purpose and the equipment to prepare, approved by staff;
- events (IADE-wide, off-site, workshops) as a separate layer;
- multi-select filters, for example two professors at once;
- a TV showing both rooms, with the timetable, bookings and events;
- inventory across two storage tiers.

The inventory is also the Master's thesis prototype ("everything starts with the storage"). The thesis L1 scope is inventory, the two storage tiers, issue and return, the timetable as a demand signal, and a minimal Godot view.

One core database serves both the lab system and the thesis. The structure follows UNIDCOM RIMS: Supabase as the source of truth, a gated Flutter back office, and a public static site generated from approved rows.

## Decisions

| Topic | Decision |
|---|---|
| Purpose | One shared core; the lab system and the thesis inventory are two clients built in parallel |
| Database | Supabase cloud, as in RIMS. Self-hosting later is a migration, not a rewrite |
| Public site + TV | Jaspr, static build |
| Back office | Flutter web, reusing RIMS patterns (auth, nav, query layer) |
| Freshness | Static rebuild triggered by a DB webhook on approval, live in about 2 min; plus a 6-hourly timetable run |
| Sign-in | Staff only, email magic link, allowlisted addresses. Professors and students request by email |
| Repo | New monorepo `openlabtwin`. `iade-lab-schedule` stays live until the TV switches over |
| Stationary equipment | An item attached to an activity, not a place |
| Google Calendar feed | Retired. Existing TechClub events are imported once |

## Architecture

```
openlabtwin/
  packages/core/        Dart models + validation shared by site and office
  apps/site/            Jaspr → static HTML: schedule, TV view, lab pages
  apps/office/          Flutter web back office (staff)
  supabase/migrations/  schema, RLS, grants, audit trigger
  scripts/timetable.py  IADE scraper (ported from iade-lab-schedule), upserts lessons
  scripts/export.py     approved rows → apps/site/data/*.json, field allowlist
```

Data flow:

```
IADE timetable ──6h──► timetable.py ──► lessons ─┐
                                                 ├─► Supabase ──webhook on approve──► GitHub Action
staff ──magic link──► office (Flutter) ──────────┘                                     export.py → Jaspr build → Pages
                                                                                        TV page re-fetches JSON every few min
```

## Data model

Stock is not a stored number. It is a view summing `movements`, which gives the event history the thesis measures.

- **places**: `id, name, kind (room|storage), tier (fast|long, storage only), parent_id, iade_name, public`. `iade_name` is the exact room name on the IADE timetable, used to attach lessons to rooms.
- **items**: `id, name, kind (consumable|portable|stationary), unit`. Quantity-based in v1.
- **movements**: `id, item_id, qty, from_place, to_place, kind (receive|issue|return|move|consume|adjust), person_id, activity_id, by_staff, at`. Append-only.
- **stock** (view): `Σ qty` per `(item, place)`, derived from `movements`.
- **people**: `id, name, kind (staff|professor|student|external), email (private), auth_user_id, is_staff`.
- **organizations**: `id, name, kind (club|course|project)`. TechLab and RobotClub are rows here.
- **activities**: bookings and events in one table.
  - `id, title, layer (booking|event)`
  - `kind (class|consultation|club|workshop|equipment|maintenance|external)`
  - `place_ids[], location_text` (off-site events use `location_text` and no places)
  - `starts_at, ends_at, rrule, exdates[]`
  - `status (requested|approved|rejected|cancelled|done)`
  - `requester_id (private), requester_display, owner_staff_id, organization_id`
  - `attendees, purpose (private), public_note`
- **activity_items**: `activity_id, item_id, qty, prepared`. Holds the equipment to prepare, the booked stationary equipment (e.g. the laser cutter) and expected consumables. It is the "known demand" signal for the thesis.
- **lessons**: scraper output with the current fields (`date, start, end, course, teachers[], groups[], rooms[], type, programmes[], degrees[]`), plus `hash` for upserts.
- **audit_log**: filled by a trigger on every write to the tables above.

Worked example: Prof. Cláudia emails a class request.

- She becomes a `people` row; her email stays private.
- The class becomes an `activity` (`requester_display = "Prof. Cláudia"`, status `requested`, then `approved`).
- Her equipment list becomes `activity_items` rows, ticked `prepared` on the day.
- Issuing the kit is a set of `movements` from long-term to fast storage to the class, linked to the activity.

## Privacy (three layers, as in RIMS)

1. **Grants.** The anonymous role has no grants on any table.
2. **RLS.** Authenticated staff (listed in `people` with `is_staff`) can read and write everything. Nobody else can do anything.
3. **Export allowlist.** `export.py` builds each record with an explicit field list and fails the run if a record carries a key outside it. It runs with the service key, which bypasses RLS, so this layer is load-bearing on its own.
   - activities (status `approved` only): `title, layer, kind, places | location_text, times, requester_display, organization, public_note`
   - all lessons
   - places where `public` is true
   - Never exported: emails, `purpose`, `activity_items`, `movements`, stock.

## Public site and TV (apps/site)

- **Parity with the current site.** List, day, week and month views; URL-encoded filters; up to 5 favourites; a collapsible filter block; the Today, This week and All pages.
- **Multi-select filters.** Values within one field are ORed and fields are ANDed. In the URL this is a repeated key: `?teacher=A&teacher=B&room=X`.
- **Professor / staff filter.** Lesson teachers plus `requester_display` of activities.
- **Three layers**, each with its own colour: the official timetable (the current red accent), bookings (blue, `#1e5cb3` / `#82b1ff`), and events (green, `#1eb350` / `#80ffaa`). Blue and green are the red accent's hue rotated, keeping the same saturation and lightness.
- **TV view.** Both lab rooms side by side for today and what's next, plus upcoming events. It re-fetches JSON every few minutes and keeps showing the last good data if the network is down.
- **Weeks start on Monday.** The export keeps the whole current week, which fixes the missing earlier days.
- **`lab.ics`** stays available at an equivalent URL.

## Back office (apps/office)

Pages for v1:

- **Requests and activities.** List, create, edit, approve or reject, and repeat rules.
- **Activity detail.** Equipment list with "prepared" ticks, and "issue kit", which creates the movements.
- **Items and stock** by place and tier. Receive, move and adjust.
- **Issue and return.** Who has what and what is overdue.
- **People and organizations.**

Reused from RIMS: the magic-link auth flow, the `SideNav` / nav model pattern, a single query file (`lib/data/supabase.dart`), and the `needsAuth` route gate.

## Errors and failure modes

- **Timetable scrape looks broken** (too few lessons, too many failed pages). Exit before writing, as today. `lessons` keeps its last good rows.
- **Export allowlist violation.** The run fails and nothing is deployed.
- **Webhook or Action failure.** The site keeps its last build. The 6-hourly run catches up.
- **Supabase down.** The public site and TV are unaffected because they're static. Only the back office is unavailable.
- **Clashes.** An approved activity that overlaps a lesson or another approved activity in the same place, or the same stationary item, shows a warning in the office. It is not blocked, because staff decide.

## Testing

- **SQL tests** (pgTAP or plain SQL asserts, run in CI against a local Supabase):
  - anon can read nothing;
  - non-staff can write nothing;
  - the stock view equals the sum of movements.
- **`export.py`:**
  - the allowlist rejects extra keys;
  - unapproved activities are never exported;
  - rrule expansion including `exdates` (ported from the current `bookings()` test).
- **`timetable.py`:** the current `tests/test_parse.py` fixtures, ported.
- **`packages/core`:** Dart unit tests for multi-select filter logic and overlap layout (ported from `tests/test_calendar.mjs`).
- **One Maestro or browser flow:** create an activity, approve it, see it in the exported JSON.

## Milestones (each gets its own implementation plan)

1. **Core.** Monorepo skeleton, Supabase schema + RLS + grants + audit, `timetable.py` writing `lessons`, `export.py` writing JSON matching the current `all.json` shape.
2. **Public site parity + multi-select + TV view** in Jaspr, reading the exported JSON. Then switch the TV over.
3. **Back office activities.** Requests, approval, equipment lists, the webhook-triggered rebuild. Import the TechClub calendar once and retire the feed.
4. **Inventory.** Items, places and tiers, movements, stock, issue and return. This is thesis L1 data collection.
5. **Thesis layer.** Demand forecast (reactive vs history vs history + timetable + activities) and the minimal Godot view reading Supabase. Out of scope for this spec; it builds on 1–4.

## Out of scope for v1

- Serial-numbered assets and RFID/QR tagging (a later `assets` table)
- Procurement and suppliers
- Sign-in for professors and students
- Consultation self-booking
- Linking lesson teachers to `people` rows
- Local-first edge nodes (thesis, later)
- Godot beyond the milestone 5 demonstrator
