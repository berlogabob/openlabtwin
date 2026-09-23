# OpenLabTwin

Core data for the IADE game lab: rooms, storage, equipment, people, bookings and events, plus the official IADE timetable. The lab's public schedule and TV (milestone 2) and the staff back office (milestone 3) are built on it. It is also the prototype for the Master's thesis.

Design: `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md`

## How it works

- `supabase/migrations/` holds the schema. Only staff (a `people` row with `is_staff`) can read or write. The anonymous role has no grants at all.
- `scripts/timetable.py` scrapes the IADE timetable every 6 hours and upserts `lessons` from this week's Monday onward. Older lessons are kept as history.
- `scripts/export.py` writes `apps/site/web/data/all.json` and `apps/site/web/calendar/lab.ics` from lessons and **approved** activities. It uses explicit columns and a key allowlist (`KEYS`), so emails, purposes, equipment lists and stock never leave the database.
- `.github/workflows/sync.yml` scrapes the timetable every 6 hours. Every 10 minutes it runs only the export, so approved bookings reach the site within about 15 minutes. It commits the data when it changes, then builds `apps/site` and `apps/office` and deploys both to GitHub Pages. A deploy happens on every push and every 6-hour run, and on a 10-minute run only when the data changed.

## Back office

`apps/office` is a Flutter web app at https://berlogabob.github.io/openlabtwin/office/. Staff sign in with a link sent to their email. Sign-ups are disabled, so only accounts an admin creates can sign in. There, staff log bookings and events: who asked (the email stays private), what for, the rooms or an off-site location, the time, and an optional weekly repeat with skipped dates. They also record the equipment to prepare and tick it off as prepared, see clash warnings against lessons and other approved bookings, and approve, reject, cancel or mark done. Only approved rows are exported, with the public fields only.

Inventory: the Inventory button in the office's top bar opens a list of every item with its stock per place (fast storage, long-term storage, rooms) and who has what on loan. "Record movement" handles receive, move, issue, return, consume and adjust. Every change is a new row in `movements`: stock is never edited in place, and a mistake is corrected with an `adjust`. On a booking, "Issue kit" and "Return kit" record the whole equipment list at once, linked to that booking. Issuing more than a place holds shows a warning with "Issue anyway", not a block. A stationary item (laser cutter, 3D printer) booked by two approved bookings at the same time shows up as a clash. The `stock` and `on_loan` views are staff-only, and the public export never includes them.

Add a staff member:

1. `POST $SUPABASE_URL/auth/v1/admin/users` with the service key and `{"email": "...", "email_confirm": true}`. The response gives the new `id`.
2. `insert into people (name, kind, email, is_staff, auth_user_id) values ('Name', 'staff', 'email', true, '<id>')`, for example with `uv run python scripts/sqltest.py`'s `query()` or the SQL editor.

The office test: `cd apps/office && flutter analyze && flutter test`. For browser tests, build with `--dart-define=E2E=true` to turn on the accessibility tree that Playwright reads.

The old Google Calendar bookings feed is retired.

## Site

`apps/site` is a static [Jaspr](https://jaspr.site) site. Both pages fetch `data/all.json` in the browser.

- Schedule: https://berlogabob.github.io/openlabtwin/. Every filter takes several values (`?teacher=A&teacher=B`): values within a field are ORed, and fields are ANDed. `room=` with no value means any room. Bookings show in blue and events in green.
- Lab TV: https://berlogabob.github.io/openlabtwin/tv/?room=A&room=B shows the rooms side by side for today, plus upcoming events. It reloads every 5 minutes and keeps the last data if the network drops. Without `room`, it shows the Tech Lab.
- Calendar: https://berlogabob.github.io/openlabtwin/calendar/lab.ics

Locally: `cd apps/site && dart test && jaspr serve` (install the CLI once with `dart pub global activate jaspr_cli 0.23.4`). The page logic is in `lib/schedule.dart` and `lib/calendar.dart`; the pages are in `lib/pages/`.

## Run locally

No Docker and no Postgres port needed: migrations and database tests go over HTTPS (Supabase Management API). Once: `supabase login` in a real terminal, `supabase link --project-ref <ref>`, and `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` in `.env`. Then:

```bash
uv sync
uv run python scripts/sqltest.py          # apply migrations + pgTAP tests (each rolls back); --seed loads seed.sql
for t in tests/test_*.py; do uv run python "$t"; done
set -a; . ./.env; set +a
uv run python scripts/timetable.py && uv run python scripts/export.py
```

## Production

- Apply migrations: `uv run python scripts/sqltest.py`. It goes over HTTPS, which matters because the IADE network blocks Postgres ports; `supabase db push` works where those ports are open, and both record migrations in the same history table. There are no down migrations; write the inverse by hand.
- GitHub secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (the service role key; never commit it, never use it in a browser).
- Seed rows (Tech Lab, the two storage tiers, TechLab and RobotClub) are loaded once with `uv run python scripts/sqltest.py --seed`. The production project `openlabtwin` (ref `huqecytswaswkswofrqd`) is already seeded.
