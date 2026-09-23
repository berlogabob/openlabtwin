# Milestone 1: Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Supabase database holding the lab's core data (places, items, movements, people, organizations, activities, lessons), with access locked to staff. The IADE timetable is scraped into it, and approved data is exported to an `all.json` in the same shape as the current site's.

**Architecture:**
- **Schema:** SQL migrations under `supabase/`, tested with pgTAP against the hosted Supabase project (no Docker), each test rolled back.
- **Scripts:** two Python scripts talk to Supabase with the service key.
  - `timetable.py` ports the existing scraper and upserts `lessons`.
  - `export.py` builds the public JSON through a field allowlist.
- **Helpers:** pure logic (parsing, row mapping, sync planning, repeat expansion, allowlist) is separated from the thin database calls, so it can be tested without a database.

**Tech Stack:**
- Supabase (Postgres 15+, RLS, pgTAP run with psql by `scripts/sqltest.sh`), Supabase CLI 2.x, libpq
- Python ≥ 3.11 managed with `uv`, using `supabase` (Python client) and `python-dateutil`
- GitHub Actions

**Spec:** `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md`

## Global Constraints

- Python tooling is `uv` only (`uv add`, `uv run`, `uv sync`). Never pip or venv.
- `requires-python = ">=3.11"`. No backslashes inside f-string expressions (3.11 rejects them).
- Python dependencies: stdlib + `supabase` + `python-dateutil`. Nothing else.
- Time zone: `Europe/Lisbon` for every date and time shown to people.
- The anonymous role has **no** grants on any table or view.
- RLS: only authenticated users whose `people` row has `is_staff = true` can read or write. Everyone else can do nothing.
- `export.py` builds records from explicit fields only and fails the run if a record has a key outside `KEYS`. Emails, `purpose`, `requester_id`, `activity_items`, `movements` and stock are never exported, and never even selected.
- Export record shape: `date, start, end, course, groups, teachers, type, rooms, programmes, degrees` (the current `all.json` shape) plus `layer` (`lesson|booking|event`) and `note`.
- Lessons are kept from the **Monday of the current week** onward, not from today.
- `movements` is append-only for staff. Corrections are new `adjust` rows.
- Supabase's API returns at most 1000 rows per request, so every read goes through `db.fetch_all` (paginated).
- Commits end with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk
  ```

## Prerequisites (one-time, on the developer machine)

- **No Docker.** Database tests run against the hosted Supabase project, not a local one.
- The hosted Supabase project `openlabtwin` (EU region) exists. `.env` in the repo root (gitignored) holds:
  - `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`;
  - `DB_URL`, the session pooler connection string (`postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`).
- `psql` from `brew install libpq`. It's keg-only; `scripts/sqltest.sh` finds it with `brew --prefix libpq`.
- Supabase CLI ≥ 2.0 (`supabase --version`; 2.117.0 is installed).
- `scripts/sqltest.sh` pushes migrations with `supabase db push --db-url` and then runs each `supabase/tests/database/*.sql` with psql. It fails on `not ok`, a test-count mismatch or an SQL error. Test files wrap themselves in `begin … rollback`, so they leave no data behind.
- The old repo is available at `~/Documents/GitHub/IADE_Schedule`. Task 3 copies code and fixtures from it.

## File Structure

```
openlabtwin/
  pyproject.toml                         uv project for scripts/
  .gitignore
  README.md                              runbook
  supabase/
    config.toml                          from `supabase init`
    seed.sql                             Tech Lab, two storage tiers, TechLab/RobotClub
    migrations/
      20260923120000_core_schema.sql     tables + stock view
      20260923120100_access.sql          audit log, is_staff(), RLS, grants
    tests/database/
      01_schema.test.sql                 stock maths, shape constraints
      02_access.test.sql                 anon / non-staff / staff, append-only, audit
  scripts/
    timetable_parse.py                   ported fetch + parse from iade-lab-schedule, plus monday_of()
    db.py                                connect(), fetch_all() pagination, chunks()
    timetable.py                         to_rows(), plan_sync(), main(): scrape → upsert lessons
    export.py                            build(), assert_whitelist(), render(), main(): DB → all.json
  tests/
    fixture_turma.html, fixture_multiweek.html   copied from iade-lab-schedule
    test_timetable.py
    test_db.py
    test_export.py
  .github/workflows/
    test.yml                             python tests + pgTAP on a CI-only local Supabase (GitHub runs Docker, not you)
    sync.yml                             every 6 h: timetable.py, export.py, commit apps/site/data
  apps/site/data/all.json                written by export.py (the site in milestone 2 reads it)
```

---

### Task 1: Core schema

**Files:**
- Create: `supabase/config.toml` (via `supabase init`)
- Create: `supabase/migrations/20260923120000_core_schema.sql`
- Create: `supabase/seed.sql`
- Create: `supabase/tests/database/01_schema.test.sql`
- Create: `.gitignore`

**Interfaces:**
- Produces:
  - tables `places, items, people, organizations, activities, activity_items, movements, lessons`
  - view `stock(item_id, place_id, qty)`
  - the column names below, which Tasks 2–4 use verbatim

- [ ] **Step 1: Initialise Supabase and .gitignore**

```bash
cd ~/Documents/GitHub/openlabtwin
supabase init            # answer "N" to the VS Code / IntelliJ settings prompts
printf '.venv/\n__pycache__/\nsupabase/.temp/\nsupabase/.branches/\n.env\n' > .gitignore
```

- [ ] **Step 2: Write the failing schema test**

Create `supabase/tests/database/01_schema.test.sql`:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into items (name, kind) values ('Test ESP32', 'portable');
insert into places (name, kind, tier) values ('Test long', 'storage', 'long'), ('Test fast', 'storage', 'fast');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 30, p.id, 'receive' from items i, places p where i.name = 'Test ESP32' and p.name = 'Test long';
insert into movements (item_id, qty, from_place, to_place, kind)
  select i.id, 12, l.id, f.id, 'move' from items i, places l, places f
  where i.name = 'Test ESP32' and l.name = 'Test long' and f.name = 'Test fast';

select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Test long'),
          18::numeric, 'move takes stock out of the source');
select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Test fast'),
          12::numeric, 'move puts stock into the target');
select throws_ok($$insert into movements (item_id, qty, kind) select id, 1, 'receive' from items where name = 'Test ESP32'$$,
                 '23514', null, 'receive without a target place is rejected');
select throws_ok($$insert into places (name, kind) values ('Test shelf', 'storage')$$,
                 '23514', null, 'storage needs a tier');

select * from finish();
rollback;
```

- [ ] **Step 3: Run it to verify it fails**

Run: `scripts/sqltest.sh`
Expected: FAIL. `✗ supabase/tests/database/01_schema.test.sql (SQL error)` with `relation "items" does not exist`.

- [ ] **Step 4: Write the schema migration**

Create `supabase/migrations/20260923120000_core_schema.sql`:

```sql
-- Core lab data. See docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md, "Data model".

create table places (
  id        bigint generated always as identity primary key,
  name      text not null unique,
  kind      text not null check (kind in ('room', 'storage')),
  tier      text check (tier in ('fast', 'long')),
  parent_id bigint references places (id),
  iade_name text unique,              -- exact room name on the IADE timetable
  public    boolean not null default false,
  check ((kind = 'storage') = (tier is not null))
);

create table items (
  id   bigint generated always as identity primary key,
  name text not null unique,
  kind text not null check (kind in ('consumable', 'portable', 'stationary')),
  unit text not null default 'pcs'
);

create table people (
  id           bigint generated always as identity primary key,
  name         text not null,
  kind         text not null check (kind in ('staff', 'professor', 'student', 'external')),
  email        text unique,
  auth_user_id uuid unique references auth.users (id) on delete set null,
  is_staff     boolean not null default false
);

create table organizations (
  id   bigint generated always as identity primary key,
  name text not null unique,
  kind text not null check (kind in ('club', 'course', 'project'))
);

create table activities (
  id                bigint generated always as identity primary key,
  title             text not null,
  layer             text not null check (layer in ('booking', 'event')),
  kind              text not null check (kind in ('class', 'consultation', 'club', 'workshop', 'equipment', 'maintenance', 'external')),
  place_ids         bigint[] not null default '{}',
  location_text     text,             -- off-site events: no places, a free-text location
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  rrule             text,             -- RFC 5545 RRULE body, e.g. FREQ=WEEKLY;COUNT=10 (UNTIL in local form, no Z)
  exdates           date[] not null default '{}',
  status            text not null default 'requested' check (status in ('requested', 'approved', 'rejected', 'cancelled', 'done')),
  requester_id      bigint references people (id),
  requester_display text,
  owner_staff_id    bigint references people (id),
  organization_id   bigint references organizations (id),
  attendees         int check (attendees >= 0),
  purpose           text,             -- private
  public_note       text,
  created_at        timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table activity_items (
  activity_id bigint not null references activities (id) on delete cascade,
  item_id     bigint not null references items (id),
  qty         numeric not null check (qty > 0),
  prepared    boolean not null default false,
  primary key (activity_id, item_id)
);

create table movements (
  id          bigint generated always as identity primary key,
  item_id     bigint not null references items (id),
  qty         numeric not null,
  from_place  bigint references places (id),
  to_place    bigint references places (id),
  kind        text not null check (kind in ('receive', 'issue', 'return', 'move', 'consume', 'adjust')),
  person_id   bigint references people (id),    -- who holds it (issue / return)
  activity_id bigint references activities (id),
  by_staff    bigint references people (id),
  at          timestamptz not null default now(),
  constraint movement_shape check (case kind
    when 'receive' then from_place is null and to_place is not null and qty > 0
    when 'issue'   then from_place is not null and to_place is null and person_id is not null and qty > 0
    when 'return'  then from_place is null and to_place is not null and person_id is not null and qty > 0
    when 'move'    then from_place is not null and to_place is not null and from_place <> to_place and qty > 0
    when 'consume' then from_place is not null and to_place is null and qty > 0
    when 'adjust'  then from_place is null and to_place is not null and qty <> 0
  end)
);

-- Stock is never stored: it is the sum of movements, per item and place.
create view stock with (security_invoker = true) as
select item_id, place_id, sum(qty) as qty
from (
  select item_id, to_place as place_id, qty from movements where to_place is not null
  union all
  select item_id, from_place, -qty from movements where from_place is not null
) m
group by item_id, place_id;

create table lessons (
  id         bigint generated always as identity primary key,
  hash       text not null unique,       -- sha1 of date|start|end|course|rooms, see scripts/timetable.py
  date       date not null,
  start_time time not null,
  end_time   time not null,
  course     text not null,
  teachers   text[] not null default '{}',
  groups     text[] not null default '{}',
  rooms      text[] not null default '{}',
  type       text not null default '',
  programmes text[] not null default '{}',
  degrees    text[] not null default '{}'
);
create index lessons_date on lessons (date);
```

- [ ] **Step 5: Write the seed**

Create `supabase/seed.sql`. Loaded once into the hosted project with psql (Task 1 Step 6).

```sql
insert into places (name, kind, tier, iade_name, public) values
  ('Tech Lab', 'room', null, 'Lab. e Estudo de Jogos - Tech Lab (Oriente)', true),
  ('Fast storage', 'storage', 'fast', null, false),
  ('Long-term storage', 'storage', 'long', null, false);
insert into organizations (name, kind) values ('TechLab', 'club'), ('RobotClub', 'club');
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `scripts/sqltest.sh`
Expected: the migration is pushed, then `✓ supabase/tests/database/01_schema.test.sql (4 passed)`.
Then load the seed once: `set -a; . ./.env; set +a; "$(brew --prefix libpq)/bin/psql" "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql`

- [ ] **Step 7: Commit**

```bash
git add .gitignore supabase
git commit -m "Core schema: places, items, movements, stock view, people, activities, lessons

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 2: Access control and audit

**Files:**
- Create: `supabase/migrations/20260923120100_access.sql`
- Create: `supabase/tests/database/02_access.test.sql`

**Interfaces:**
- Consumes: the Task 1 tables.
- Produces:
  - `is_staff() returns boolean`
  - table `audit_log(id, table_name, row_id, op, old_row, new_row, actor, at)`
  - the rule that only `service_role` writes `lessons`

- [ ] **Step 1: Write the failing access test**

Create `supabase/tests/database/02_access.test.sql`:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'staff@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'someone@example.com');
insert into people (name, kind, email, auth_user_id, is_staff)
  values ('Staff', 'staff', 'staff@example.com', '00000000-0000-0000-0000-00000000000a', true);
insert into lessons (hash, date, start_time, end_time, course) values ('h1', '2026-10-01', '09:00', '10:00', 'X');

set local role anon;
select throws_ok('select * from lessons', '42501', null, 'anon cannot read lessons');
select throws_ok('select * from people', '42501', null, 'anon cannot read people');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is_empty('select * from people', 'signed-in non-staff sees no people');
select throws_ok($$insert into items (name, kind) values ('Hack', 'portable')$$, '42501', null, 'non-staff cannot write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select isnt_empty('select * from lessons', 'staff reads lessons');
select lives_ok($$insert into items (name, kind) values ('Audited ESP32', 'portable')$$, 'staff writes items');
select throws_ok('delete from movements', '42501', null, 'movements are append-only for staff');
reset role;

select is((select count(*)::int from audit_log where table_name = 'items' and op = 'INSERT'
           and new_row ->> 'name' = 'Audited ESP32'), 1, 'item insert is audited');

select * from finish();
rollback;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `scripts/sqltest.sh`
Expected: `02_access.test.sql` FAILS. The first failure is `anon cannot read lessons` (anon still has Supabase's default grants), or `relation "audit_log" does not exist`.

- [ ] **Step 3: Write the access migration**

Create `supabase/migrations/20260923120100_access.sql`:

```sql
-- Who may touch what. Three layers, as in UNIDCOM RIMS: grants (tables), RLS (rows), export allowlist (fields).

create table audit_log (
  id         bigint generated always as identity primary key,
  table_name text not null,
  row_id     bigint,
  op         text not null,
  old_row    jsonb,
  new_row    jsonb,
  actor      uuid default auth.uid(),
  at         timestamptz not null default now()
);

create function audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (table_name, row_id, op, old_row, new_row)
  values (tg_table_name,
          coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id')::bigint,
          tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;

-- ponytail: lessons are not audited; the scraper rewrites thousands every 6 h. Git history of all.json covers them.
do $$ declare t text; begin
  foreach t in array array['places', 'items', 'people', 'organizations', 'activities', 'activity_items', 'movements'] loop
    execute format('create trigger audit after insert or update or delete on %I for each row execute function audit()', t);
  end loop;
end $$;

create function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from people where auth_user_id = auth.uid() and is_staff)
$$;

do $$ declare t text; begin
  foreach t in array array['places', 'items', 'people', 'organizations', 'activities', 'activity_items', 'movements', 'lessons'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;
alter table audit_log enable row level security;
create policy staff_read on audit_log for select to authenticated using (is_staff());

-- Grants: anon gets nothing, now and for future tables.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon, public;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon, public;
grant execute on function is_staff() to authenticated;

-- Staff write rules the policies can't express.
revoke update, delete, truncate on movements from authenticated;         -- append-only; corrections are 'adjust' rows
revoke insert, update, delete, truncate on audit_log from authenticated;
revoke insert, update, delete, truncate on lessons from authenticated;   -- only the scraper (service_role) writes lessons
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `scripts/sqltest.sh`
Expected: `✓ …01_schema.test.sql (4 passed)` and `✓ …02_access.test.sql (8 passed)`.

- [ ] **Step 5: Commit**

```bash
git add supabase
git commit -m "Access: staff-only RLS, no anon grants, append-only movements, audit log

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 3: Timetable parser port and lesson rows

**Files:**
- Create: `pyproject.toml`, `uv.lock` (via uv)
- Create: `scripts/timetable_parse.py` (generated from the old `fetch.py`)
- Create: `scripts/timetable.py` (pure functions only in this task)
- Create: `tests/fixture_turma.html`, `tests/fixture_multiweek.html` (copied)
- Test: `tests/test_timetable.py`

**Interfaces:**
- Produces, in `timetable_parse`:
  - `BASE`, `TZ`
  - `get(url) -> str`
  - `group_programmes(index_html) -> dict[str, str]`
  - `degree(programme) -> str`
  - `find_pages(index_html, today) -> list[str]`
  - `parse_page(page_html, source_url="") -> list[dict]`
  - `all_lessons_unique(lessons) -> list[dict]`
  - `monday_of(d: date) -> date`
- Produces, in `timetable`:
  - `lesson_hash(l: dict) -> str`
  - `to_rows(lessons: list[dict], programmes: dict[str, str]) -> list[dict]`. Row keys: `hash, date, start_time, end_time, course, teachers, groups, rooms, type, programmes, degrees`.
  - `plan_sync(existing_hashes: list[str], rows: list[dict]) -> tuple[list[dict], list[str]]`, returning the upserts and the hashes to delete.

- [ ] **Step 1: Create the uv project**

```bash
cd ~/Documents/GitHub/openlabtwin
uv init --bare --name openlabtwin-scripts
sed -i '' 's/^requires-python = .*/requires-python = ">=3.11"/' pyproject.toml   # uv writes the local Python's version
uv add supabase python-dateutil
mkdir -p scripts tests
cp ~/Documents/GitHub/IADE_Schedule/tests/fixture_turma.html ~/Documents/GitHub/IADE_Schedule/tests/fixture_multiweek.html tests/
```

- [ ] **Step 2: Generate `scripts/timetable_parse.py` from the old scraper**

This copies the named fetch and parse definitions verbatim and leaves out the rendering and booking code.

```bash
uv run python - <<'EOF'
import ast, pathlib
src = (pathlib.Path.home() / "Documents/GitHub/IADE_Schedule/scripts/fetch.py").read_text(encoding="utf-8")
keep = ["BASE", "TZ", "DAYS", "LINK_RE", "TIME_RE", "TREE_RE", "DEGREES", "get", "group_programmes", "degree",
        "find_pages", "_Cells", "_brackets", "parse_cell", "week_mondays", "parse_page", "all_lessons_unique"]
found = {}
for node in ast.parse(src).body:
    name = getattr(node, "name", None) or (node.targets[0].id if isinstance(node, ast.Assign) else None)
    if name in keep:
        found[name] = ast.get_source_segment(src, node)
assert not set(keep) - set(found), set(keep) - set(found)
header = '''"""IADE timetable fetch + parse, ported verbatim from iade-lab-schedule/scripts/fetch.py."""
import html
import re
import time
import urllib.request
from datetime import date, datetime, timedelta
from html.parser import HTMLParser
from zoneinfo import ZoneInfo
'''
footer = '''

def monday_of(d):
    """Monday of d's week; the schedule always starts there, not at today."""
    return d - timedelta(days=d.weekday())
'''
body = "\n\n\n".join(found[k] for k in keep)
pathlib.Path("scripts/timetable_parse.py").write_text(header + "\n\n" + body + "\n" + footer, encoding="utf-8")
EOF
```

- [ ] **Step 3: Write the failing test**

Create `tests/test_timetable.py`:

```python
"""Run: uv run python tests/test_timetable.py"""
import sys
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "scripts"))
import timetable  # noqa: E402
import timetable_parse as tp  # noqa: E402

# --- ported parser checks (same fixtures and asserts as iade-lab-schedule/tests/test_parse.py)
ls = tp.parse_page((HERE / "fixture_turma.html").read_text(encoding="utf-8-sig"))
got = sorted((l["date"], l["start"], l["end"]) for l in ls)
assert got == [("2026-12-14", "14:00", "16:30"), ("2026-12-15", "13:00", "17:00"), ("2026-12-16", "13:00", "17:00"),
               ("2026-12-17", "14:00", "16:30"), ("2026-12-18", "13:00", "17:00")], got
l = ls[0]
assert l["course"] == "Exploração Profissional I / Professional Exploration I"
assert l["groups"] == ["LDGL001D01", "LDGL001D02", "LDGL001D03"]
assert l["teachers"] == ["Pedro Machado", "Tânia Fernandes"]
assert l["type"] == "P"
assert l["rooms"] == ["Sala 012 (Oriente)", "Sala 013 (Oriente)", "Sala 014 (Oriente)", "Sala 015 (Oriente)"]

html = (HERE / "fixture_multiweek.html").read_text(encoding="utf-8-sig")
ms = tp.week_mondays(html)
assert len(ms) == 10 and ms[0].isoformat() == "2026-10-12" and ms[-1].isoformat() == "2026-12-14"
assert len(tp.parse_page(html)) % 10 == 0

idx = 'href="turma_A_1_20260921.html?1" href="turma_B_2_2026092120261005.html?1" href="turma_C_3_20260901.html?1"'
assert tp.find_pages(idx, datetime(2026, 9, 30).date()) == ["turma_B_2_2026092120261005.html"]

tree = """<li>IADE: Mestrado em Computação Criativa e Inteligência Artificial<ul>
<li>Ano 1<ul>
<li>IADE M-CIA 1ºS<ul>
<li>MCIA001N01<ul>
<li><a href="turma_MCIA001N01_452_20260907.html">Semanas</a></li>
<li>IADE: Licenciatura em Desenvolvimento de Jogos<ul>
<li>LDJO001D01<ul>"""
progs = tp.group_programmes(tree)
assert progs == {"MCIA001N01": "Mestrado em Computação Criativa e Inteligência Artificial",
                 "LDJO001D01": "Licenciatura em Desenvolvimento de Jogos"}, progs
assert tp.degree("Erasmus 2022") == "Other"

# --- the week starts on Monday
assert tp.monday_of(date(2026, 9, 23)) == date(2026, 9, 21)
assert tp.monday_of(date(2026, 9, 21)) == date(2026, 9, 21)

# --- rows for the lessons table
base = {"date": "2026-10-01", "start": "09:00", "end": "12:00", "course": "X", "teachers": ["T"], "type": "P",
        "rooms": ["Sala 1"], "source_url": "u"}
rows = timetable.to_rows([base | {"groups": ["G1"]}, base | {"groups": ["G2"]}], {"G1": "Mestrado em Y"})
assert len(rows) == 1, rows
r = rows[0]
assert set(r) == {"hash", "date", "start_time", "end_time", "course", "teachers", "groups", "rooms", "type",
                  "programmes", "degrees"}, r
assert r["groups"] == ["G1", "G2"] and r["programmes"] == ["Mestrado em Y"] and r["degrees"] == ["Master"]
assert r["start_time"] == "09:00" and r["end_time"] == "12:00"
assert r["hash"] == timetable.to_rows([base | {"groups": ["G9"]}], {})[0]["hash"], "hash must ignore groups"
assert r["hash"] != timetable.to_rows([base | {"groups": ["G1"], "end": "13:00"}], {})[0]["hash"]

# --- sync plan: upsert everything scraped, delete what vanished from the source
up, gone = timetable.plan_sync(["a", "b", "c"], [{"hash": "b"}, {"hash": "d"}])
assert [x["hash"] for x in up] == ["b", "d"] and gone == ["a", "c"]
print("ok")
```

- [ ] **Step 4: Run it to verify it fails**

Run: `uv run python tests/test_timetable.py`
Expected: FAIL. `ModuleNotFoundError: No module named 'timetable'`.

- [ ] **Step 5: Write the pure part of `scripts/timetable.py`**

```python
"""Scrape the IADE timetable into the lessons table.

Usage: SUPABASE_URL=... SUPABASE_SERVICE_KEY=... uv run python scripts/timetable.py
"""
import hashlib

from timetable_parse import all_lessons_unique, degree


def lesson_hash(l):
    """Identity of a lesson across runs: the same key all_lessons_unique() merges on (groups excluded)."""
    return hashlib.sha1("|".join([l["date"], l["start"], l["end"], l["course"], *l["rooms"]]).encode()).hexdigest()


def to_rows(lessons, programmes):
    rows = []
    for l in all_lessons_unique(lessons):
        progs = sorted({programmes[g] for g in l["groups"] if g in programmes})
        rows.append({"hash": lesson_hash(l), "date": l["date"], "start_time": l["start"], "end_time": l["end"],
                     "course": l["course"], "teachers": l["teachers"], "groups": l["groups"], "rooms": l["rooms"],
                     "type": l["type"], "programmes": progs, "degrees": sorted({degree(p) for p in progs})})
    return rows


def plan_sync(existing_hashes, rows):
    """Upsert every scraped row; delete stored rows (this week onward) the source no longer lists."""
    return rows, sorted(set(existing_hashes) - {r["hash"] for r in rows})
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `uv run python tests/test_timetable.py`
Expected: `ok`. If you get a `NameError` from `timetable_parse.py`, a ported function uses a module that isn't in the header. Add the import to the header in Step 2 and rerun Step 2.

- [ ] **Step 7: Commit**

```bash
git add pyproject.toml uv.lock scripts tests
git commit -m "Timetable: port the IADE parser, lesson rows with stable hashes, sync plan

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 4: Database helpers and the timetable run

**Files:**
- Create: `scripts/db.py`
- Modify: `scripts/timetable.py` (add `main()`)
- Test: `tests/test_db.py`

**Interfaces:**
- Consumes:
  - `timetable_parse.BASE, TZ, get, find_pages, parse_page, group_programmes, monday_of`
  - `timetable.to_rows, plan_sync`
- Produces, in `db`:
  - `connect()`, which returns a Supabase client or exits with the names of any missing env vars
  - `fetch_all(query_factory) -> list[dict]`. `query_factory` must return a fresh, ordered query builder each call.
  - `chunks(seq, n=500) -> list[list]`

- [ ] **Step 1: Write the failing test**

Create `tests/test_db.py`:

```python
"""Run: uv run python tests/test_db.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import db  # noqa: E402


class FakeQuery:
    """Mimics a PostgREST builder: .range(a, b) then .execute().data, capped at 1000 rows like the real API."""

    def __init__(self, rows):
        self.rows, self.window = rows, None

    def range(self, a, b):
        self.window = (a, min(b, a + 999))
        return self

    def execute(self):
        a, b = self.window
        return type("Result", (), {"data": self.rows[a:b + 1]})()


rows = [{"id": i} for i in range(2500)]
assert db.fetch_all(lambda: FakeQuery(rows)) == rows, "must page past the 1000-row cap"
assert db.fetch_all(lambda: FakeQuery(rows[:1000])) == rows[:1000], "exact page boundary"
assert db.fetch_all(lambda: FakeQuery([])) == []
assert db.chunks(range(5), 2) == [[0, 1], [2, 3], [4]]
assert db.chunks([], 2) == []
print("ok")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `uv run python tests/test_db.py`
Expected: FAIL. `ModuleNotFoundError: No module named 'db'`.

- [ ] **Step 3: Write `scripts/db.py`**

```python
"""Thin Supabase access for the batch scripts. Service key only: it bypasses RLS, so callers select explicit columns."""
import os
import sys

PAGE = 1000  # PostgREST's default max rows per request


def connect():
    missing = [n for n in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY") if not os.environ.get(n)]
    if missing:
        sys.exit(f"Missing environment variables: {', '.join(missing)}")
    from supabase import create_client  # imported here so the pure tests don't need network setup

    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def fetch_all(query_factory):
    """Every row of a query, one PAGE at a time. query_factory() must return a fresh builder with an .order()."""
    rows, start = [], 0
    while True:
        page = query_factory().range(start, start + PAGE - 1).execute().data or []
        rows += page
        if len(page) < PAGE:
            return rows
        start += PAGE


def chunks(seq, n=500):
    seq = list(seq)
    return [seq[i:i + n] for i in range(0, len(seq), n)]
```

- [ ] **Step 4: Run it to verify it passes**

Run: `uv run python tests/test_db.py`
Expected: `ok`

- [ ] **Step 5: Add `main()` to `scripts/timetable.py`**

Replace the import block at the top of `scripts/timetable.py` with:

```python
import hashlib
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from db import chunks, connect, fetch_all
from timetable_parse import (BASE, TZ, all_lessons_unique, degree, find_pages, get, group_programmes, monday_of,
                             parse_page)
```

Append to the end of `scripts/timetable.py`:

```python
def main():
    today = datetime.now(TZ).date()
    monday = monday_of(today).isoformat()
    index_html = get(BASE)
    pages = find_pages(index_html, today)
    print(f"Pages found: {len(pages)}")
    if not pages:
        sys.exit("No timetable pages found. Source format may have changed.")

    lessons, failed = [], 0
    with ThreadPoolExecutor(max_workers=4) as pool:  # ponytail: 4 workers keeps load on the IADE server polite
        futures = {name: pool.submit(lambda n: parse_page(get(BASE + n), BASE + n), name) for name in pages}
        for name, f in futures.items():
            try:
                lessons += [l for l in f.result() if l["date"] >= monday]
            except Exception as ex:  # one broken page must not stop the run
                failed += 1
                if failed <= 5:
                    print(f"  failed {name}: {ex!r}", file=sys.stderr)
    print(f"Pages parsed: {len(pages) - failed}\nPages failed: {failed}\nLessons found: {len(lessons)}")
    # sanity check before touching the database: never replace a good schedule with a broken one
    if len(lessons) < 10 or failed > len(pages) // 2:
        sys.exit("Too few lessons or too many failures. Source format may have changed.")

    rows = to_rows(lessons, group_programmes(index_html))
    client = connect()
    existing = [r["hash"] for r in fetch_all(
        lambda: client.table("lessons").select("hash").gte("date", monday).order("id"))]
    upserts, deletes = plan_sync(existing, rows)
    for c in chunks(upserts):
        client.table("lessons").upsert(c, on_conflict="hash").execute()
    for c in chunks(deletes, 100):  # hashes go in the URL; 100 keeps it short
        client.table("lessons").delete().in_("hash", c).execute()
    print(f"Upserted: {len(upserts)}\nDeleted: {len(deletes)}")


if __name__ == "__main__":
    main()
```

Lessons from before this Monday are never deleted. They stay as history for the thesis.

- [ ] **Step 6: Run the timetable against the hosted database**

```bash
set -a; . ./.env; set +a
uv run python scripts/timetable.py
uv run python scripts/timetable.py   # second run: same upserts, 0 deleted
uv run python tests/test_timetable.py && uv run python tests/test_db.py
```

Expected: the first run prints `Pages found: N` (N > 0), then `Upserted: M` with M in the thousands and `Deleted: 0`. The second run prints the same `Upserted: M` and `Deleted: 0`. Both tests print `ok`.

- [ ] **Step 7: Commit**

```bash
git add scripts tests
git commit -m "Timetable run: paginated reads, chunked upsert and delete of this week onward

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 5: Export with field allowlist

**Files:**
- Create: `scripts/export.py`
- Test: `tests/test_export.py`

**Interfaces:**
- Consumes:
  - `db.connect, fetch_all`
  - `timetable_parse.TZ, monday_of`
  - DB columns from Task 1
- Produces:
  - `KEYS: frozenset`
  - `build(lessons, activities, places, organizations, today) -> list[dict]`
  - `assert_whitelist(records)`, which raises `AssertionError`
  - `render(records) -> str`
  - `main()`, which writes `apps/site/data/all.json`, or `<argv[1]>/all.json` if a directory is given

- [ ] **Step 1: Write the failing test**

Create `tests/test_export.py`:

```python
"""Run: uv run python tests/test_export.py"""
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import export  # noqa: E402

places = [{"id": 1, "name": "Tech Lab", "iade_name": "Lab. e Estudo de Jogos - Tech Lab (Oriente)", "public": True},
          {"id": 2, "name": "Long-term storage", "iade_name": None, "public": False}]
orgs = [{"id": 7, "name": "RobotClub"}]
lesson = {"date": "2026-09-21", "start_time": "09:00:00", "end_time": "11:00:00", "course": "Game Frameworks",
          "groups": ["G1"], "teachers": ["T"], "type": "P", "rooms": ["Sala 1"], "programmes": ["P"],
          "degrees": ["Bachelor"]}
club = {"id": 1, "title": "Club meeting", "layer": "booking", "kind": "club", "place_ids": [1, 2],
        "location_text": None, "starts_at": "2026-10-20T16:00:00+00:00", "ends_at": "2026-10-20T18:00:00+00:00",
        "rrule": "FREQ=WEEKLY;COUNT=3", "exdates": ["2026-10-27"], "status": "approved",
        "requester_display": "Prof. Cláudia", "organization_id": 7, "public_note": "Bring laptops"}
fair = {"id": 2, "title": "Open day", "layer": "event", "kind": "external", "place_ids": [],
        "location_text": "Aula Magna", "starts_at": "2026-09-25T09:00:00+00:00", "ends_at": "2026-09-25T12:00:00+00:00",
        "rrule": None, "exdates": [], "status": "approved", "requester_display": None, "organization_id": None,
        "public_note": None}
pending = club | {"id": 3, "title": "Secret", "status": "requested", "rrule": None}

out = export.build([lesson, lesson | {"date": "2026-09-20"}], [club, fair, pending], places, orgs, date(2026, 9, 23))

assert all(set(r) == export.KEYS for r in out), out
assert not any(r["course"] == "Secret" for r in out), "unapproved activity was exported"
assert [r["date"] for r in out if r["layer"] == "lesson"] == ["2026-09-21"], "keep from this Monday, drop Sunday before"
assert out[0]["start"] == "09:00" and out[0]["note"] == ""

clubs = [r for r in out if r["course"] == "Club meeting"]
assert [r["date"] for r in clubs] == ["2026-10-20", "2026-11-03"], "weekly repeat minus the exdate"
assert all(r["start"] == "17:00" and r["end"] == "19:00" for r in clubs), "wall-clock time kept across DST (25 Oct)"
c = clubs[0]
assert c["rooms"] == ["Lab. e Estudo de Jogos - Tech Lab (Oriente)"], "public places only, by their IADE name"
assert c["teachers"] == ["Prof. Cláudia"] and c["groups"] == ["RobotClub"] and c["type"] == "Club"
assert c["layer"] == "booking" and c["note"] == "Bring laptops" and c["programmes"] == [] and c["degrees"] == []

f = next(r for r in out if r["course"] == "Open day")
assert f["rooms"] == ["Aula Magna"] and f["layer"] == "event" and f["teachers"] == [] and f["groups"] == []
assert f["start"] == "10:00" and f["note"] == ""

try:
    export.assert_whitelist([out[0] | {"email": "x@example.com"}])
except AssertionError:
    pass
else:
    raise SystemExit("allowlist let an extra key through")

text = export.render(out)
assert text.startswith("[\n{") and text.endswith("}\n]\n") and json.loads(text) == out
print("ok")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `uv run python tests/test_export.py`
Expected: FAIL. `ModuleNotFoundError: No module named 'export'`.

- [ ] **Step 3: Write `scripts/export.py`**

```python
"""Export approved data to the public schedule JSON.

Usage: SUPABASE_URL=... SUPABASE_SERVICE_KEY=... uv run python scripts/export.py [out_dir]

Runs with the service key, which bypasses RLS: the explicit column lists and KEYS allowlist are what keep
emails, purposes, equipment lists and stock out of the public site.
"""
import json
import sys
from datetime import datetime, time, timedelta
from pathlib import Path

from dateutil.rrule import rrulestr

from db import connect, fetch_all
from timetable_parse import TZ, monday_of

ROOT = Path(__file__).resolve().parent.parent
WINDOW_DAYS = 180  # how far ahead repeating activities are expanded
KEYS = frozenset({"date", "start", "end", "course", "groups", "teachers", "type", "rooms", "programmes", "degrees",
                  "layer", "note"})
LESSON_COLS = "id,date,start_time,end_time,course,groups,teachers,type,rooms,programmes,degrees"
ACTIVITY_COLS = ("id,title,layer,kind,place_ids,location_text,starts_at,ends_at,rrule,exdates,status,"
                 "requester_display,organization_id,public_note")


def lesson_record(r):
    return {"date": r["date"], "start": r["start_time"][:5], "end": r["end_time"][:5], "course": r["course"],
            "groups": r["groups"], "teachers": r["teachers"], "type": r["type"], "rooms": r["rooms"],
            "programmes": r["programmes"], "degrees": r["degrees"], "layer": "lesson", "note": ""}


def occurrences(a, first, last):
    """(start, end) local datetimes of an activity between two dates. Repeats run on Lisbon wall-clock time."""
    start = datetime.fromisoformat(a["starts_at"]).astimezone(TZ).replace(tzinfo=None)
    length = datetime.fromisoformat(a["ends_at"]) - datetime.fromisoformat(a["starts_at"])
    if a.get("rrule"):
        starts = rrulestr(a["rrule"], dtstart=start).between(datetime.combine(first, time.min),
                                                            datetime.combine(last, time.max), inc=True)
    else:
        starts = [start] if first <= start.date() <= last else []
    skip = set(a.get("exdates") or [])
    return [(s, s + length) for s in starts if s.date().isoformat() not in skip]


def activity_records(a, place_names, org_names, first, last):
    rooms = [place_names[p] for p in a["place_ids"] if p in place_names]
    if not rooms and a.get("location_text"):
        rooms = [a["location_text"]]
    org = org_names.get(a.get("organization_id"))
    return [{"date": s.date().isoformat(), "start": s.strftime("%H:%M"), "end": e.strftime("%H:%M"),
             "course": a["title"], "groups": [org] if org else [],
             "teachers": [a["requester_display"]] if a.get("requester_display") else [],
             "type": a["kind"].capitalize(), "rooms": rooms, "programmes": [], "degrees": [],
             "layer": a["layer"], "note": a.get("public_note") or ""}
            for s, e in occurrences(a, first, last)]


def assert_whitelist(records):
    for r in records:
        stray = set(r) - KEYS
        assert not stray, f"record {r.get('course')!r} {r.get('date')} has forbidden keys: {sorted(stray)}"


def build(lessons, activities, places, organizations, today):
    first = monday_of(today)
    last = first + timedelta(days=WINDOW_DAYS)
    place_names = {p["id"]: p["iade_name"] or p["name"] for p in places if p["public"]}
    org_names = {o["id"]: o["name"] for o in organizations}
    out = [lesson_record(r) for r in lessons if r["date"] >= first.isoformat()]
    for a in activities:
        if a["status"] == "approved":  # also filtered in the query; checked again so a query change can't leak
            out += activity_records(a, place_names, org_names, first, last)
    assert_whitelist(out)
    return sorted(out, key=lambda r: (r["date"], r["start"], r["course"]))


def render(records):
    """One record per line, like the current all.json, so git diffs stay readable."""
    return "[\n" + ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in records) + "\n]\n"


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "apps/site/data"
    today = datetime.now(TZ).date()
    monday = monday_of(today).isoformat()
    client = connect()
    lessons = fetch_all(lambda: client.table("lessons").select(LESSON_COLS).gte("date", monday).order("id"))
    activities = fetch_all(
        lambda: client.table("activities").select(ACTIVITY_COLS).eq("status", "approved").order("id"))
    places = fetch_all(lambda: client.table("places").select("id,name,iade_name,public").order("id"))
    organizations = fetch_all(lambda: client.table("organizations").select("id,name").order("id"))
    records = build(lessons, activities, places, organizations, today)
    if not any(r["layer"] == "lesson" for r in records):
        sys.exit("No lessons to export; refusing to publish an empty schedule.")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "all.json").write_text(render(records), encoding="utf-8")
    print(f"Exported {len(records)} records "
          f"({sum(r['layer'] == 'lesson' for r in records)} lessons) to {out_dir / 'all.json'}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run it to verify it passes**

Run: `uv run python tests/test_export.py`
Expected: `ok`

- [ ] **Step 5: Export from the local database and compare with the live site**

Load `.env` as in Task 4 Step 6. The hosted database must hold that run's lessons.

```bash
uv run python scripts/export.py
uv run python - <<'EOF'
import json, urllib.request
new = [r for r in json.load(open("apps/site/data/all.json")) if r["layer"] == "lesson"]
old = json.load(urllib.request.urlopen("https://berlogabob.github.io/iade-lab-schedule/all.json"))
print("new lessons:", len(new), "old lessons:", len(old), "new first date:", new[0]["date"])
EOF
```

Expected:
- `Exported N records`.
- The new lesson count is **at least** the old count. It includes the earlier days of this week, which the old site drops.
- The first date is this week's Monday.

- [ ] **Step 6: Commit**

```bash
git add scripts tests apps/site/data/all.json
git commit -m "Export: approved lessons and activities to all.json through a field allowlist

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 6: CI, scheduled sync, runbook, go-live

**Files:**
- Create: `.github/workflows/test.yml`
- Create: `.github/workflows/sync.yml`
- Create: `README.md`

**Interfaces:**
- Consumes: `scripts/timetable.py`, `scripts/export.py`, `tests/test_*.py`, `supabase/tests/database/*.sql`.
- Produces: the GitHub secrets `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` (set by the user), which milestone 3's webhook-triggered rebuild reuses.

- [ ] **Step 1: Write `.github/workflows/test.yml`**

```yaml
name: Test

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      - name: Python tests
        run: for t in tests/test_*.py; do uv run python "$t"; done
      - uses: supabase/setup-cli@v1
        with:
          version: latest
      - run: supabase db start
      - name: Database tests
        run: supabase test db
```

- [ ] **Step 2: Write `.github/workflows/sync.yml`**

```yaml
name: Sync timetable and export

on:
  workflow_dispatch:
  schedule:
    - cron: "15 */6 * * *" # every 6 hours (UTC)

permissions:
  contents: write

concurrency:
  group: sync
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-latest
    env:
      SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
      SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
      - run: uv sync --locked
      - run: for t in tests/test_*.py; do uv run python "$t"; done
      # both scripts exit non-zero before writing if something looks wrong; the last good all.json stays published
      - run: uv run python scripts/timetable.py
      - run: uv run python scripts/export.py
      - name: Commit if changed
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add apps/site/data
          if git diff --cached --quiet; then
            echo "No changes"
          else
            git commit -m "Sync schedule"
            git push
          fi
```

- [ ] **Step 3: Write `README.md`**

````markdown
# OpenLabTwin

Core data for the IADE game lab: rooms, storage, equipment, people, bookings and events, plus the official IADE timetable. The lab's public schedule and TV (milestone 2) and the staff back office (milestone 3) are built on it. It is also the prototype for the Master's thesis.

Design: `docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md`

## How it works

- `supabase/migrations/` holds the schema. Only staff (a `people` row with `is_staff`) can read or write. The anonymous role has no grants at all.
- `scripts/timetable.py` scrapes the IADE timetable every 6 hours and upserts `lessons` from this week's Monday onward. Older lessons are kept as history.
- `scripts/export.py` writes `apps/site/data/all.json` from lessons and **approved** activities. It uses explicit columns and a key allowlist (`KEYS`), so emails, purposes, equipment lists and stock never leave the database.
- `.github/workflows/sync.yml` runs both scripts and commits `all.json` when it changes.

## Run locally

No Docker needed. The database tests run against the hosted project. Put `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` and `DB_URL` (session pooler string) in `.env`, then:

```bash
uv sync
brew install libpq                        # psql, used by scripts/sqltest.sh
scripts/sqltest.sh                        # push migrations + pgTAP tests (each rolls back)
for t in tests/test_*.py; do uv run python "$t"; done
set -a; . ./.env; set +a
uv run python scripts/timetable.py && uv run python scripts/export.py
```

## Production

- Apply migrations: `supabase link --project-ref <ref>`, then `supabase db push`. There are no down migrations; write the inverse by hand.
- GitHub secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (the service role key; never commit it, never use it in a browser).
- Seed rows (Tech Lab, the two storage tiers, TechLab and RobotClub) are not applied by `db push`. Run `supabase/seed.sql` once in the SQL editor.
````

- [ ] **Step 4: Run all local checks**

```bash
for t in tests/test_*.py; do uv run python "$t"; done
scripts/sqltest.sh
```

Expected: three `ok` lines, then two `✓` lines.

- [ ] **Step 5: Commit**

```bash
git add .github README.md
git commit -m "CI tests, 6-hourly timetable sync + export, runbook

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

- [ ] **Step 6: Go-live. The user performs or approves each step; these touch external services.**

1. Create the GitHub repo and push: `gh repo create berlogabob/openlabtwin --public --source . --push`. Public is needed for free GitHub Pages in milestone 2. `all.json` holds only public data.
2. The Supabase project already exists (Prerequisites). The migrations and seed were applied in Tasks 1–2.
3. (nothing: `scripts/sqltest.sh` already pushed the migrations)
4. In the SQL editor, create the first staff row: `insert into people (name, kind, email, is_staff) values ('Andrey Dyakov', 'staff', '<your email>', true);`. Its `auth_user_id` is linked at first sign-in in milestone 3.
5. `gh secret set SUPABASE_URL` and `gh secret set SUPABASE_SERVICE_KEY`, pasting the values when prompted.
6. `gh workflow run "Sync timetable and export"`, then `gh run watch`.

Expected:
- The **Test** workflow is green.
- The sync run is green and commits `apps/site/data/all.json`.
- Its lesson count is at least that of `https://berlogabob.github.io/iade-lab-schedule/all.json`, and its first date is this Monday.

`iade-lab-schedule` keeps running unchanged until milestone 2 switches the TV over.

---

## Spec coverage (milestone 1)

| Spec item | Task |
|---|---|
| Monorepo skeleton | 1, 3, 6 (`apps/site/data` only; `packages/core` and the apps arrive with milestones 2 and 3, the first code that needs them) |
| Schema: places, items, movements, stock view, people, organizations, activities, activity_items, lessons | 1 |
| audit_log trigger | 2 (lessons excluded, noted in the migration) |
| Privacy layer 1: no anon grants | 2 |
| Privacy layer 2: staff-only RLS | 2 |
| Privacy layer 3: export allowlist | 5 |
| Timetable scraper writing lessons; broken-source guard | 3, 4 |
| Weeks start on Monday (earlier days fix) | 3, 4, 5 |
| Repeating activities with exdates, expanded in export | 5 |
| Only approved activities exported; only public places exported | 5 |
| Export matching the current all.json shape | 5 (plus `layer` and `note`) |
| SQL tests: anon reads nothing, non-staff writes nothing, stock equals movements | 1, 2 |
| export.py tests: allowlist, unapproved, rrule + exdates | 5 |
| Ported parser tests | 3 |
| 6-hourly run; last good version kept on failure | 6 |

Deferred to later milestones:
- **Milestone 2:** `places.json` for the site, `lab.ics`, the Dart `packages/core` filter tests.
- **Milestone 3:** the webhook-triggered rebuild, clash warnings, and the one-time TechClub calendar import.
