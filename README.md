# OpenLabTwin

Core data for the IADE game lab: rooms, storage, equipment, people, bookings and events, plus the official IADE timetable. The lab's public schedule and TV (milestone 2) and the staff back office (milestone 3) are built on it. It is also the prototype for the Master's thesis.

Design: `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md`

## How it works

- `supabase/migrations/` holds the schema. Only staff (a `people` row with `is_staff`) can read or write. The anonymous role has no grants at all.
- `scripts/timetable.py` scrapes the IADE timetable every 6 hours and upserts `lessons` from this week's Monday onward. Older lessons are kept as history.
- `scripts/export.py` writes `apps/site/data/all.json` from lessons and **approved** activities. It uses explicit columns and a key allowlist (`KEYS`), so emails, purposes, equipment lists and stock never leave the database.
- `.github/workflows/sync.yml` runs both scripts and commits `all.json` when it changes.

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
