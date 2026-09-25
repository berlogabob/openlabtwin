# OpenLabTwin

The IADE game lab's system of record: rooms, storage, equipment, people, bookings, events, and the official IADE timetable. The public schedule, the lab TV and the staff back office are all built on it. It is also the working prototype for the Master's thesis ("everything starts with the storage").

| | URL |
|---|---|
| Schedule (public) | https://berlogabob.github.io/openlabtwin/ |
| Lab TV (showcase: videos, bios, event takeovers; lab network or Tailscale) | http://192.168.1.131/tv/?room=Lab.+e+Estudo+de+Jogos+-+Tech+Lab+(Oriente) |
| Lab TV (same layout, QR codes and events only; anywhere) | https://berlogabob.github.io/openlabtwin/tv/?room=Lab.+e+Estudo+de+Jogos+-+Tech+Lab+(Oriente) |
| Calendar feed | https://berlogabob.github.io/openlabtwin/calendar/lab.ics |
| Book a consultation (QR) | https://berlogabob.github.io/openlabtwin/book/ |
| Share an idea (QR) | https://berlogabob.github.io/openlabtwin/ideas/ |
| Back office (staff) | https://berlogabob.github.io/openlabtwin/office/ |

## Documentation

- [Architecture](docs/ARCHITECTURE.md): the parts, how data flows, the three privacy layers, and why each decision was made.
- [Operations](docs/OPERATIONS.md): the runbook. Publishing, secrets, staff and rooms, migrations, tests, troubleshooting.
- [Staff guide](docs/STAFF-GUIDE.md): for lab technicians using the back office, the TV and the public site.
- [Edge node](docs/edge-node.md): the always-on lab machine (TechLAB-01): publishing, idea AI, the showcase TV, backups; the lab network, Tailscale, the TV computer.
- [Roadmap](docs/ROADMAP.md): what's next.
- History: the design spec and the per-milestone implementation plans in [`docs/superpowers/`](docs/superpowers/).

## Repo map

```
supabase/migrations/   schema, row-level security, grants, audit      supabase/tests/database/  pgTAP tests
scripts/               timetable.py (scrape), export.py (public JSON + lab.ics), db.py (PostgREST over urllib),
                       sqltest.py (migrations + DB tests over HTTPS), publish.sh + edge-setup.sh (edge node), backup.py, ideas_ai.py, tv.py,
                       ics.py, timetable_parse.py
tests/                 Python tests (plain asserts: uv run python tests/test_x.py)
apps/site/             public site + TV (Jaspr, static)                 apps/office/  back office (Flutter web)
apps/tv/               showcase TV (plain HTML, served by the edge node)
.github/workflows/     sync.yml (scrape, export, build, deploy)          test.yml (Python, TV page, site, office tests)
```

## Quick start (development)

```bash
uv sync
for t in tests/test_*.py; do uv run python "$t"; done       # Python
uv run python scripts/sqltest.py                             # DB migrations + pgTAP (needs `supabase login` + link)
(cd apps/site && dart test)                                  # site logic
(cd apps/office && flutter test)                             # office logic
uv run --with playwright python tests/check_tv_page.py      # showcase TV page in Chrome
```

Everything database-side goes over HTTPS, so there's no Docker and no Postgres port. The reason is in [Operations → Network](docs/OPERATIONS.md#network).
