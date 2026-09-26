# Smart storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Files go to local pi on **Unsloth Studio** (`PI_PROVIDER=studio PI_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`) through `pi_task.py`: "create or replace file = block", time-boxed, anything unfinished is written from the plan. The controller runs every shell step and all verification, and checks each file byte for byte against this plan.

**Goal:** real places with codes and QR labels, tagged items (assets), a stocktake that replaces the untrusted spreadsheet with counted numbers, a Needs-attention queue (RIMS patterns), the spreadsheet import, and a read-only mirror of the database on the edge node.

**Architecture:** two migrations (storage core, then quality), one import script, the office (Places, place screen, stocktake, Needs attention, tagged items in the movement form, `?place=` deep link), a label script, and a mirror script with edge-setup step 10.

**Spec:** `docs/superpowers/specs/2026-09-26-smart-storage-design.md`.

## Ponytail

- **Needs attention** is one view, not a table per rule. Waivers are a single text key. The duplicate check is an items × items self-join, fine for hundreds of items.
- **The mirror** guesses column types from the JSON, with timestamps chosen by name. It rebuilds everything each night.
- **The deep link** is lost on first sign-in (the magic link drops the query), because staff stay signed in on their phones.
- **Labels** are one HTML page printed from the browser, with no PDF step.
- **Deferred:** RFID, a public "report broken" page (Jaspr), and Godot code.

---

### Task 1: Storage core (places codes, assets, asset_place)

- [ ] **Step 1 (pi): create `supabase/tests/database/07_smart_storage.test.sql`**

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'storage-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Storage staff', 'staff', '00000000-0000-0000-0000-0000000000c1', true);
insert into people (name, kind) values ('Storage student', 'student');
insert into items (name, kind) values ('Test Quest', 'portable'), ('Test cable', 'consumable');
insert into places (name, kind, tier, code) values ('Test shelf', 'storage', 'fast', 'T-S1');
insert into assets (item_id, serial) select id, 'SN-TEST-1' from items where name = 'Test Quest';

select throws_ok($$insert into places (name, kind, tier, code) values ('Bad', 'storage', 'fast', 'r15 left')$$,
                 '23514', null, 'a code is capitals, digits and dashes');
select matches((select tag from assets where serial = 'SN-TEST-1'), '^TL-[0-9]{4}$', 'an untagged asset gets the next TL number');
select lives_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select a.item_id, a.id, 1, p.id, 'receive' from assets a, places p where a.serial = 'SN-TEST-1' and p.code = 'T-S1'$$,
                'an asset is received one at a time');
select throws_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select a.item_id, a.id, 2, p.id, 'receive' from assets a, places p where a.serial = 'SN-TEST-1' and p.code = 'T-S1'$$,
                 '23514', null, 'an asset movement has quantity 1');
select throws_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select i.id, a.id, 1, p.id, 'receive' from assets a, items i, places p
  where a.serial = 'SN-TEST-1' and i.name = 'Test cable' and p.code = 'T-S1'$$,
                 '23503', null, 'an asset moves only as its own item');
select is((select p.code from asset_place ap join assets a on a.id = ap.asset_id join places p on p.id = ap.place_id
           where a.serial = 'SN-TEST-1'), 'T-S1', 'received: the asset is on the shelf');
insert into movements (item_id, asset_id, qty, from_place, person_id, kind)
  select a.item_id, a.id, 1, p.id, s.id, 'issue' from assets a, places p, people s
  where a.serial = 'SN-TEST-1' and p.code = 'T-S1' and s.name = 'Storage student';
select is((select s.name from asset_place ap join assets a on a.id = ap.asset_id join people s on s.id = ap.person_id
           where a.serial = 'SN-TEST-1' and ap.place_id is null), 'Storage student', 'issued: the student holds it');
insert into movements (item_id, asset_id, qty, to_place, person_id, kind)
  select a.item_id, a.id, 1, p.id, s.id, 'return' from assets a, places p, people s
  where a.serial = 'SN-TEST-1' and p.code = 'T-S1' and s.name = 'Storage student';
select is((select p.code from asset_place ap join assets a on a.id = ap.asset_id join places p on p.id = ap.place_id
           where a.serial = 'SN-TEST-1'), 'T-S1', 'returned: back on the shelf');

set local role anon;
select throws_ok('select * from assets', '42501', null, 'anon cannot read assets');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select lives_ok($$insert into assets (item_id) select id from items where name = 'Test cable'$$, 'staff add assets (tag from the sequence)');
reset role;

select * from finish();
rollback;
```

- [ ] **Step 2 (controller):** `uv run python scripts/sqltest.py` → `07_smart_storage` fails (column `code` does not exist).

- [ ] **Step 3 (pi): create `supabase/migrations/20260926100000_smart_storage.sql`**

```sql
-- Smart storage (docs/superpowers/specs/2026-09-26-smart-storage-design.md): place codes, individual assets, stocktake.
-- A place's code is printed on its QR label and is the node name in the Godot twin, so it stays fixed once labelled.

alter table places
  add column code text unique check (code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$'),
  add column counted_at timestamptz;   -- last stocktake; null = never counted, so its numbers are unconfirmed

update places set code = 'LAB' where name = 'Tech Lab';
update places set code = 'R15', name = 'Room 15 (gabinete)' where name = 'Fast storage';
update places set code = 'B2', name = '-2 floor storage' where name = 'Long-term storage';

alter table items
  add column note text,
  add column merged_into bigint references items (id);   -- set by merge_items(); the office hides merged items

create sequence asset_tag;
create table assets (
  id        bigint generated always as identity primary key,
  item_id   bigint not null references items (id),
  tag       text not null unique default 'TL-' || lpad(nextval('asset_tag')::text, 4, '0'),   -- or a legacy tag (GS-031, LV-01)
  serial    text unique,
  condition text not null default 'ok' check (condition in ('ok', 'broken', 'missing')),
  note      text,
  seen_at   timestamptz,               -- last ticked in a stocktake
  unique (id, item_id)
);
alter table assets enable row level security;
create policy staff_all on assets for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on assets for each row execute function audit();
revoke all on assets from anon;

-- An asset moves one at a time and only as its own item; merging items moves its movements along (on update cascade).
alter table movements
  add column asset_id bigint,
  add column note text,                -- provenance: 'import: …', 'stocktake'
  add constraint movement_asset foreign key (asset_id, item_id) references assets (id, item_id) on update cascade,
  add constraint movement_asset_one check (asset_id is null or abs(qty) = 1);

-- Where each asset is now: its latest movement. Issued = held by a person; consumed or adjusted away = nowhere.
create view asset_place with (security_invoker = true) as
select distinct on (asset_id) asset_id,
       case when kind in ('issue', 'consume') or (kind = 'adjust' and qty < 0) then null else to_place end as place_id,
       case when kind = 'issue' then person_id end as person_id,
       at
from movements
where asset_id is not null
order by asset_id, at desc, id desc;
revoke all on asset_place from anon;
```

- [ ] **Step 4 (pi): replace `scripts/backup.py`**

```python
"""Nightly off-site backup: every table as JSON under a dated folder. The Supabase free plan keeps no backups.

Usage: uv run python scripts/backup.py [dir]      (default ~/openlabtwin-backups; keeps the newest KEEP days)
The files hold private data (emails, purposes), so the folder is created mode 700 and lives outside the repo.
Restore: insert each table's rows back in TABLES order (parents first) with the service key.
"""
import json
import os
import sys
from datetime import date
from pathlib import Path

from db import connect, select

TABLES = ["places", "items", "people", "organizations", "consultation_hours", "activities", "activity_items", "assets", "movements", "lessons",
          "audit_log"]  # parents before children
KEEP = 30


def prune(days, keep):
    """Dated folder names (YYYY-MM-DD) to delete so only the newest `keep` remain."""
    return sorted(days)[:-keep] if len(days) > keep else []


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "openlabtwin-backups")
    out = root / date.today().isoformat()
    out.mkdir(parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    db = connect()
    for t in TABLES:
        rows = select(db, t, {"select": "*", "order": "id" if t != "activity_items" else "activity_id,item_id"})
        (out / f"{t}.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        print(f"{t}: {len(rows)}")
    for old in prune([p.name for p in root.iterdir() if p.is_dir() and len(p.name) == 10], KEEP):
        for f in (root / old).iterdir():
            f.unlink()
        (root / old).rmdir()
        print(f"pruned {old}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5 (pi): replace `tests/test_backup.py`**

```python
"""Run: uv run python tests/test_backup.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import backup  # noqa: E402

days = ["2026-09-03", "2026-09-01", "2026-09-02", "2026-09-04"]
assert backup.prune(days, 2) == ["2026-09-01", "2026-09-02"], "oldest go first"
assert backup.prune(days, 4) == [] and backup.prune([], 30) == []
assert backup.TABLES.index("activities") < backup.TABLES.index("activity_items") < backup.TABLES.index("audit_log")
assert backup.TABLES.index("items") < backup.TABLES.index("assets") < backup.TABLES.index("movements")
print("ok")
```

- [ ] **Step 6 (controller):** `uv run python scripts/sqltest.py` → `applied 20260926100000_smart_storage.sql`, then ✓ for every test file. `uv run python tests/test_backup.py` → `ok`.

- [ ] **Commit**

```bash
git add supabase scripts/backup.py tests/test_backup.py
git commit -m "Smart storage: place codes, tagged items (assets) and where each one is

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 2: Needs attention (storage_issues, waivers, merge_items)

- [ ] **Step 1 (pi): create `supabase/tests/database/08_storage_quality.test.sql`**

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000d1', 'quality-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Quality staff', 'staff', '00000000-0000-0000-0000-0000000000d1', true);
insert into items (name, kind) values ('Comandos PS4 Brancos', 'portable'), ('Comando PS4 branco', 'portable'), ('Laser cutter', 'stationary');
insert into places (name, kind, tier, code) values ('Quality shelf', 'storage', 'fast', 'Q-S1');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 3, p.id, 'receive' from items i, places p where i.name = 'Comandos PS4 Brancos' and p.code = 'Q-S1';
insert into movements (item_id, qty, to_place, kind)
  select i.id, 2, p.id, 'receive' from items i, places p where i.name = 'Comando PS4 branco' and p.code = 'Q-S1';

select isnt_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%'$$,
                  'near-identical names are flagged');
select is_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like '%Laser%'$$, 'different names are not');
select isnt_empty($$select 1 from storage_issues s join places p on p.id = s.a_id where s.code = 'never_counted' and p.code = 'Q-S1'$$,
                  'a shelf with stock and no count needs attention');
insert into issue_waivers (key) select key from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%';
select is_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%'$$,
                'a waived issue stops showing');
select throws_ok($$select merge_items(1, array[2::bigint])$$, 'P0001', 'Only lab staff can merge items.', 'only staff merge');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select lives_ok($$select merge_items((select id from items where name = 'Comandos PS4 Brancos'),
                                     array[(select id from items where name = 'Comando PS4 branco')])$$, 'staff merge duplicates');
reset role;

select is((select s.qty from stock s join places p on p.id = s.place_id join items i on i.id = s.item_id
           where p.code = 'Q-S1' and i.name = 'Comandos PS4 Brancos'), 5::numeric, 'the survivor holds both counts');
select is((select merged_into is not null from items where name = 'Comando PS4 branco'), true, 'the duplicate stays, marked merged');

select * from finish();
rollback;
```

- [ ] **Step 2 (controller):** `uv run python scripts/sqltest.py` → `08_storage_quality` fails (relation `storage_issues` does not exist).

- [ ] **Step 3 (pi): create `supabase/migrations/20260926110000_storage_quality.sql`**

```sql
-- Needs attention for storage, the UNIDCOM RIMS way (output_quality.sql, output_merge.sql): every rule in one view,
-- waivers for false alarms, and a soft merge for duplicates.
create extension if not exists pg_trgm with schema extensions;

-- ponytail: translate() instead of unaccent, which isn't immutable and so can't feed a generated column.
alter table items add column name_norm text generated always as (
  btrim(regexp_replace(translate(lower(name), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '[^a-z0-9]+', ' ', 'g'))
) stored;
create index items_name_norm_trgm on items using gin (name_norm extensions.gin_trgm_ops);

create table issue_waivers (
  key      text primary key,           -- storage_issues.key, e.g. 'dup:12:34'
  reason   text,
  by_staff bigint references people (id),
  at       timestamptz not null default now()
);
alter table issue_waivers enable row level security;
create policy staff_all on issue_waivers for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on issue_waivers for each row execute function audit();
revoke all on issue_waivers from anon;

-- a_id / b_id: negative_stock item/place, place issues the place, duplicates both items, asset issues asset/item.
-- The stale key carries the count date, so a waiver lapses with the next count.
-- ponytail: duplicate check is an items × items self-join; fine for hundreds of items, use the % operator past that.
create view storage_issues with (security_invoker = true) as
select * from (
  select 'negative_stock' as code, s.item_id as a_id, s.place_id as b_id,
         i.name || ': ' || s.qty || ' at ' || p.name as detail, 'neg:' || s.item_id || ':' || s.place_id as key
  from stock s join items i on i.id = s.item_id join places p on p.id = s.place_id
  where s.qty < 0
  union all
  select 'never_counted', p.id, null, p.name || ' has never been counted', 'count:' || p.id
  from places p
  where p.counted_at is null and exists (select 1 from stock s where s.place_id = p.id and s.qty <> 0)
  union all
  select 'stale_count', p.id, null, p.name || ' last counted ' || to_char(p.counted_at, 'YYYY-MM-DD'),
         'stale:' || p.id || ':' || to_char(p.counted_at, 'YYYYMMDD')
  from places p
  where p.counted_at < now() - interval '180 days'
  union all
  select 'possible_duplicate', a.id, b.id, a.name || ' / ' || b.name, 'dup:' || a.id || ':' || b.id
  from items a join items b on a.id < b.id
  where a.merged_into is null and b.merged_into is null and extensions.similarity(a.name_norm, b.name_norm) > 0.5
  union all
  select 'asset_' || x.condition, x.id, x.item_id, i.name || ' ' || x.tag || ' is ' || x.condition, 'asset:' || x.id || ':' || x.condition
  from assets x join items i on i.id = x.item_id
  where x.condition <> 'ok'
) issue
where key not in (select key from issue_waivers);
revoke all on storage_issues from anon;

-- Soft merge: the duplicates' assets, movements and kit lines go to the survivor; the duplicates stay, marked merged_into.
create function merge_items(p_survivor bigint, p_losers bigint[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then
    raise exception 'Only lab staff can merge items.';
  end if;
  if p_survivor = any (p_losers) then
    raise exception 'An item cannot be merged into itself.';
  end if;
  if exists (select 1 from items where id = p_survivor and merged_into is not null) then
    raise exception 'That item was already merged into another one.';
  end if;
  update assets set item_id = p_survivor where item_id = any (p_losers);   -- their movements follow (on update cascade)
  update movements set item_id = p_survivor where item_id = any (p_losers);
  -- a booking that listed both: one kit line with both quantities
  insert into activity_items (activity_id, item_id, qty, prepared)
    select activity_id, p_survivor, sum(qty), bool_and(prepared) from activity_items where item_id = any (p_losers) group by activity_id
    on conflict (activity_id, item_id) do update set qty = activity_items.qty + excluded.qty;
  delete from activity_items where item_id = any (p_losers);
  update items set merged_into = p_survivor where id = any (p_losers);
end $$;
revoke all on function merge_items(bigint, bigint[]) from public, anon;
grant execute on function merge_items(bigint, bigint[]) to authenticated;
```

- [ ] **Step 4 (controller):** `uv run python scripts/sqltest.py` → ✓ for every test file.

- [ ] **Commit**

```bash
git add supabase
git commit -m "Storage Needs attention: one issues view, waivers, soft merge of duplicate items (RIMS patterns)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 3: Import the spreadsheet

- [ ] **Step 1 (controller):** `uv add openpyxl`.

- [ ] **Step 2 (pi): create `tests/test_import_inventory.py`**

```python
"""Run: uv run python tests/test_import_inventory.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import import_inventory as imp  # noqa: E402

for text, code in [(15, "R15"), ("13/14/15", "LAB"), (14, "LAB"), ("Vitrine13/14", "LAB-VIT"), ("Vitrine 13/14 ", "LAB-VIT"),
                   ("13 - Caixa de Servidor Cinza", "LAB-SRV"), ("15 - 3 Direito", "R15-R-S3"), ("15- 3 Direito", "R15-R-S3"),
                   ("15 -3 Direito", "R15-R-S3"), ("15 - 2 Direito ", "R15-R-S2"), ("15- 5 Esquerdo", "R15-L-S5"),
                   ("Caixa de Arrumos Verde- 15", "R15-BOX-GREEN"), ("Caixas de Sensores PascoCar 15", "R15-BOX-SENS"),
                   ("Caixa de Arrumos carros PascoCar - 15", "R15-BOX-CARS")]:
    assert imp.place_code(text) == code, (text, imp.place_code(text))
try:
    imp.place_code("Armario 17")
    raise AssertionError("unknown places must not be guessed")
except ValueError:
    pass
assert [c for c, *_ in imp.PLACES].count("R15-L-S5") == 1 and len({c for c, *_ in imp.PLACES}) == len(imp.PLACES)

for value, n in [(4, 4), ("11 + 10", 21), ("15 (7 Azuis + 8 Vermelhos)", 15), ("4 (Pé + Armação) + 3 (Armação Soltas)", 7),
                 ("Varios (100+)", 100), ("Varias", 1), ("5 + Saco extra", 5), (None, 1)]:
    assert imp.qty(value) == n, (value, imp.qty(value))

assert imp.tags("GS 031 + GS 019 + GS 003") == ["GS-031", "GS-019", "GS-003"]
assert imp.tags(" GS - 077") == ["GS-077"]
assert imp.tags("GS 089+ 090 + 092+093+095") == ["GS-089", "GS-090", "GS-092", "GS-093", "GS-095"]
assert imp.tags("GS 180(Caixa) + GS 176") == ["GS-180", "GS-176"]
assert imp.tags("PF 136 +... + PF 145") == [f"PF-{n}" for n in range(136, 146)]
assert imp.tags("LV-01") == ["LV-01"] and imp.tags("AS - 08 (GamesStudio - 025)") == ["AS-08"]
assert imp.tags("GS 023 + outro") == ["GS-023"]
assert imp.tags("PF 158+159, PF 160+161") == ["PF-158", "PF-159", "PF-160", "PF-161"]
assert imp.tags("GS004+GS020/GS033+GS032") == ["GS-004", "GS-020", "GS-033", "GS-032"]
assert imp.tags("EPSON ELPLP67") == [] and imp.tags("ME-8971") == [] and imp.tags(None) == []

inv = imp.Inventory()
inv.line("Consola PS4 Slim", "LAB-VIT", 10)
for n in range(3):
    inv.asset("Consola PS4 Slim", "LAB-VIT", serial=f"S{n}")
inv.asset("Consola PS4 Slim", "LAB-VIT", serial="S0", note="seen twice")
assert inv.receives() == [("Consola PS4 Slim", "LAB-VIT", 7)], "assets are taken out of the counted line"
assert len(inv.assets) == 3 and inv.assets["S0"]["note"] == "seen twice", "one asset per serial"
print("ok")
```

- [ ] **Step 3 (pi): create `scripts/import_inventory.py`**

```python
"""One-off import of the previous team's spreadsheet (Inventario Tech Lab.xlsx) into places, items, assets and movements.

Usage: uv run python scripts/import_inventory.py <xlsx>            dry run: prints what it would write
       uv run python scripts/import_inventory.py <xlsx> --apply    writes it (service key); refuses a second run
The spreadsheet isn't trusted: every place starts with counted_at empty, so it shows as "never counted" in the office
until someone counts it. Student loan records (PlayStation sheet) are listed, not imported: check them first.
"""
import re
import sys
from collections import Counter, defaultdict

NOTE = "import: Inventario Tech Lab.xlsx"

# code, name, tier, parent. LAB, R15 and B2 exist already (migration 20260926100000).
PLACES = [
    ("LAB-VIT", "Vitrine (Tech Lab)", "fast", "LAB"),
    ("LAB-SRV", "Grey server cabinet (Tech Lab)", "fast", "LAB"),
    ("R15-L", "Room 15 left cabinet", "fast", "R15"),
    ("R15-R", "Room 15 right cabinet", "fast", "R15"),
    *[(f"R15-{s}-S{n}", f"Room 15 {side} cabinet, shelf {n}{' (top)' if n == 1 else ' (bottom)' if n == 5 else ''}", "fast", f"R15-{s}")
      for s, side in (("L", "left"), ("R", "right")) for n in range(1, 6)],
    ("R15-BOX-GREEN", "Green storage box (room 15)", "fast", "R15"),
    ("R15-BOX-SENS", "PascoCar sensor box (room 15)", "fast", "R15"),
    ("R15-BOX-CARS", "PascoCar cars box (room 15)", "fast", "R15"),
    *[(f"CUP{n}", f"Classroom cupboard {n}", "fast", None) for n in range(1, 9)],
]
STATIONARY_AT = {"LAB", "LAB-SRV"}           # fixed in the room: screens, servers, ceiling projectors, furniture
SKIP = {"computadores fixos"}                # the Computadores sheet lists these one by one
FURNITURE_SKIP = {"Arcades", "Ecras Lenovo", "Projectores de teto"}   # already counted in the Sala 13/14 sheet
TAG = re.compile(r"\b(GS|PF|LV|AS)\s*-?\s*(\d+)", re.I)
CONSOLE = re.compile(r"^\d\d\s*-\s*\d+\s*-\s*\d+$")
PAD = re.compile(r"^\d{6} [0-9A-Z] \d{7}$")


def place_code(text):
    """The place code for a spreadsheet location. Unknown spellings raise, so nothing is guessed."""
    t = re.sub(r"\s+", " ", str(text)).strip().lower()
    if t == "15":
        return "R15"
    if t in {"13", "14", "13/14", "13/14/15"}:
        return "LAB"
    if t.startswith("vitrine"):
        return "LAB-VIT"
    if "servidor cinza" in t:
        return "LAB-SRV"
    m = re.match(r"^15 ?- ?(\d) ?(esquerdo|direito)$", t)
    if m:
        return f"R15-{'L' if m[2] == 'esquerdo' else 'R'}-S{m[1]}"
    if "verde" in t:
        return "R15-BOX-GREEN"
    if "sensores" in t:
        return "R15-BOX-SENS"
    if "carros" in t:
        return "R15-BOX-CARS"
    raise ValueError(f"unknown location: {text!r}")


def qty(value):
    """A count from the Quantidade cell: '11 + 10' -> 21, '15 (7 Azuis + 8 Vermelhos)' -> 15, 'Varios (100+)' -> 100, 'Varias' -> 1."""
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value or "")
    outside = [int(n) for n in re.findall(r"\d+", re.sub(r"\([^)]*\)", "", text))]
    if outside:
        return sum(outside)
    inside = re.findall(r"\d+", text)
    return int(inside[0]) if inside else 1


def tags(identifier):
    """Legacy asset tags in an Identificador cell: 'GS 089+ 090 + 092' -> GS-089, GS-090, GS-092; 'PF 136 +... + PF 145' is a range."""
    text = str(identifier or "")
    found = TAG.findall(text)
    if not found:
        return []
    prefix = found[0][0].upper()
    if "..." in text and len(found) == 2:
        a, b = int(found[0][1]), int(found[1][1])
        return [f"{prefix}-{n:03d}" for n in range(a, b + 1)]
    out = []
    for part in re.split(r"[+,/]", re.sub(r"\([^)]*\)", "", text)):
        m = TAG.search(part) or re.match(r"^\s*(\d+)\s*$", part)
        if m:
            p, n = (m[1].upper(), m[2]) if m.re is TAG else (prefix, m[1])
            prefix = p
            out.append(f"{p}-{int(n):03d}" if p in {"GS", "PF"} else f"{p}-{int(n):02d}")
    return out


def blank(v):
    return v is None or str(v).strip() in {"", "-", "- ", ".-"}


class Inventory:
    """What the spreadsheet says: lines (item at place, qty), assets (one row each, by tag), and what was left out."""

    def __init__(self):
        self.lines = []      # dict(item, place, qty, note)
        self.assets = {}     # tag or serial -> dict(item, place, tag, serial, condition, note)
        self.notes = defaultdict(list)
        self.skipped = []

    def line(self, item, place, n, note=None):
        item = re.sub(r"\s+", " ", item).strip()
        self.lines.append({"item": item, "place": place, "qty": n})
        if note:
            self.notes[item].append(note)

    def asset(self, item, place, tag=None, serial=None, condition="ok", note=None):
        key = tag or serial
        a = self.assets.setdefault(key, {"item": item, "place": place, "tag": tag, "serial": None, "condition": condition, "note": None})
        a["serial"] = a["serial"] or serial
        a["note"] = "; ".join(x for x in (a["note"], note) if x) or None

    def kinds(self):
        return {l["item"]: "stationary" if l["place"] in STATIONARY_AT else "portable" for l in self.lines}

    def receives(self):
        """(item, place, qty) left after the assets, which are received one by one."""
        have = Counter((a["item"], a["place"]) for a in self.assets.values())
        want = Counter()
        for l in self.lines:
            want[(l["item"], l["place"])] += l["qty"]
        return [(i, p, n - have[(i, p)]) for (i, p), n in want.items() if n - have[(i, p)] > 0]


def read_rows(inv, ws, item_col, holder_col=None):
    for r in ws.iter_rows(values_only=True):
        name, n, where, obs, ident = r[item_col:item_col + 5]
        if blank(name) or name == "Item" or blank(where) or str(where).startswith(("Prateleiras", "1 = Topo")):
            continue
        if str(name).strip().lower() in SKIP:
            continue
        place = place_code(where)
        name = str(name).strip()
        found = [] if holder_col else tags(ident)
        extra = [] if isinstance(n, (int, float)) or n is None else [f"quantity in the sheet: {n}"]
        if isinstance(n, (int, float)) and len(found) > n:   # device and box tags mixed: tag them at the stocktake
            extra.append(f"tags in the sheet: {', '.join(found)}")
            found = []
        count = len(found) if found and not isinstance(n, (int, float)) else qty(n)
        if not blank(obs):
            extra.append(str(obs).strip())
        if holder_col:
            extra.append(f"belongs to {str(ident).strip()}")
        elif not blank(ident) and not found:
            extra.append(f"identifier: {str(ident).strip()}")
        inv.line(name, place, count, "; ".join(extra) or None)
        for t in found:
            inv.asset(name, place, tag=t)


def read_computers(inv, ws):
    for r in ws.iter_rows(values_only=True):
        pid = r[1]
        if blank(pid) or pid == "Computador ID" or not TAG.search(str(pid)):
            continue
        tag = tags(pid)[0]
        specs = "; ".join(str(c).strip() for c in (r[2], r[3], r[4], r[5]) if not blank(c))
        broken = "avaria" in str(r[7] or "").lower()
        inv.asset("Computador Tech Lab", "LAB", tag=tag, condition="broken" if broken else "ok",
                  note="; ".join(x for x in (specs, str(r[7] or "").strip()) if x) or None)
    inv.line("Computador Tech Lab", "LAB", sum(1 for a in inv.assets.values() if a["item"] == "Computador Tech Lab"))


def read_furniture(inv, ws):
    rows = {str(r[1]).strip(): r for r in ws.iter_rows(values_only=True) if r[1]}
    for name, n, size in zip(rows["Item"][2:], rows["Quantidade"][2:], rows["Dimensões"][2:]):
        if name and str(name).strip() not in FURNITURE_SKIP:
            inv.line(str(name).strip(), "LAB", qty(n), re.sub(r"\s+", " ", str(size)).strip() if size else None)


def read_playstations(inv, ws):
    """Consoles (column C) and controllers (columns F and G) by serial, placed by the block header above them."""
    console_block, pad_place = None, None
    for r in ws.iter_rows(values_only=True):
        head, pads = str(r[1] or ""), str(r[5] or "")
        if head.startswith(("Consolas", "Playstations de Alunos")):
            console_block = head
        if pads.startswith("Comandos PS4"):
            pad_place = "LAB-VIT" if "Vitrine" in pads else "R15-L-S3"
        if console_block and "Alunos" in console_block and r[2] is not None and r[1] != "Nome Aluno":
            inv.skipped.append(f"student loan: {r[1]} ({r[2]}): console {r[3]}, box {r[4]}, controller {r[5]}")
            continue
        serial = str(r[2] or "").strip()
        if CONSOLE.match(serial):
            if "Fora do IADE" in console_block:
                inv.skipped.append(f"console outside IADE: {serial} {r[3]}")
            else:
                item = "Consola PS4 Classic" if "Old" in console_block else "Consola PS4 Slim"
                found = tags(r[3])
                inv.asset(item, "LAB-VIT", tag=found[0] if found else None, serial=re.sub(r"\s+", "", serial),
                          note=f"{r[1]}; {str(r[3]).strip()}")
        for cell in (r[5], r[6]):
            if pad_place and PAD.match(str(cell or "").strip()):
                item = "Comandos PS4" if pad_place == "LAB-VIT" else "Commando PS4"
                inv.asset(item, pad_place, serial=str(cell).strip())


def read_workbook(path):
    import openpyxl
    wb = openpyxl.load_workbook(path, data_only=True)
    inv = Inventory()
    read_rows(inv, wb["Inventario Sala 15"], 2)
    read_rows(inv, wb["Sala 1314"], 2)
    read_rows(inv, wb["Material de Docente"], 1, holder_col=True)
    read_computers(inv, wb["Computadores Tech Lab"])
    read_furniture(inv, wb["Inventario Mobiliario"])
    read_playstations(inv, wb["Playstations Records"])
    return inv


def report(inv):
    by_place = defaultdict(list)
    for i, p, n in inv.receives():
        by_place[p].append(f"{n} × {i}")
    for a in inv.assets.values():
        by_place[a["place"]].append(f"asset {a['tag'] or '(TL-auto)'} {a['serial'] or ''} {a['item']} {a['condition']}".rstrip())
    for p in sorted(by_place):
        print(f"\n[{p}]")
        for x in by_place[p]:
            print("  " + x)
    print(f"\n{len(inv.kinds())} items, {len(inv.assets)} assets, {len(inv.receives())} counted lines")
    if inv.skipped:
        print("\nNot imported (decide by hand):")
        for s in inv.skipped:
            print("  " + s)


def apply(inv):
    from db import connect, request, select
    db = connect()
    if select(db, "movements", {"select": "id", "note": f"eq.{NOTE}", "order": "id", "limit": "1"}):
        sys.exit("Already imported: movements with the import note exist.")
    back = {"Prefer": "return=representation"}
    places = {p["code"]: p["id"] for p in select(db, "places", {"select": "id,code", "order": "id"}) if p["code"]}
    for code, name, tier, parent in PLACES:
        if code not in places:
            row = {"code": code, "name": name, "kind": "storage", "tier": tier, "parent_id": places.get(parent)}
            places[code] = request(db, "POST", "places", {"select": "id"}, row, back)[0]["id"]
    notes = {i: "; ".join(dict.fromkeys(n)) for i, n in inv.notes.items()}
    rows = [{"name": i, "kind": k, "note": notes.get(i)} for i, k in inv.kinds().items()]
    request(db, "POST", "items", {"on_conflict": "name"}, rows, {"Prefer": "resolution=ignore-duplicates"})
    items = {i["name"]: i["id"] for i in select(db, "items", {"select": "id,name", "order": "id"})}
    moves = []
    for a in inv.assets.values():
        row = {"item_id": items[a["item"]], "serial": a["serial"], "condition": a["condition"], "note": a["note"]}
        if a["tag"]:
            row["tag"] = a["tag"]
        aid = request(db, "POST", "assets", {"select": "id"}, row, back)[0]["id"]
        moves.append({"item_id": items[a["item"]], "asset_id": aid, "qty": 1, "to_place": places[a["place"]], "kind": "receive", "note": NOTE})
    for i, p, n in inv.receives():
        moves.append({"item_id": items[i], "asset_id": None, "qty": n, "to_place": places[p], "kind": "receive", "note": NOTE})
    request(db, "POST", "movements", None, moves)
    print(f"wrote {len(moves)} movements")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    inventory = read_workbook(sys.argv[1])
    report(inventory)
    if "--apply" in sys.argv:
        apply(inventory)
```

- [ ] **Step 4 (controller):** `uv run python tests/test_import_inventory.py` → `ok`. Dry run: `uv run python scripts/import_inventory.py ~/Downloads/"Inventario Tech Lab.xlsx"` → `141 items, 83 assets, 126 counted lines`, and 13 rows under "Not imported".

- [ ] **Commit**

```bash
git add pyproject.toml uv.lock scripts/import_inventory.py tests/test_import_inventory.py
git commit -m "Import the previous team spreadsheet: strict place codes, legacy tags, every place uncounted

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 4: Office: places, stocktake, tagged items, Needs attention

- [ ] **Step 1 (pi): replace `apps/office/lib/logic.dart`**

```dart
// Booking logic with no Flutter in it, so `flutter test` covers it.
// Times are the browser's local wall clock. ponytail: staff and lab are in Lisbon; store UTC, show local.

const kinds = ['class', 'consultation', 'club', 'workshop', 'equipment', 'maintenance', 'external'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

/// Weekly repeat until a date (inclusive), in the local form the export's dateutil expects (no Z).
String? weeklyRrule(DateTime? until) =>
    until == null ? null : 'FREQ=WEEKLY;UNTIL=${isoDate(until).replaceAll('-', '')}T235959';

DateTime? untilOf(String? rrule) {
  final m = RegExp(r'UNTIL=(\d{4})(\d{2})(\d{2})').firstMatch(rrule ?? '');
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

class Activity {
  Activity({
    this.id,
    this.title = '',
    this.layer = 'booking',
    this.kind = 'class',
    List<int>? placeIds,
    this.locationText = '',
    required this.start,
    required this.end,
    this.repeatUntil,
    List<String>? exdates,
    this.status = 'requested',
    this.requesterId,
    this.requesterDisplay = '',
    this.ownerStaffId,
    this.organizationId,
    this.attendees,
    this.purpose = '',
    this.publicNote = '',
    this.contactLink = '',
  })  : placeIds = placeIds ?? [],
        exdates = exdates ?? [];

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: r['id'] as int?,
        title: r['title'] as String,
        layer: r['layer'] as String,
        kind: r['kind'] as String,
        placeIds: [for (final p in r['place_ids'] as List) p as int],
        locationText: r['location_text'] as String? ?? '',
        start: DateTime.parse(r['starts_at'] as String).toLocal(),
        end: DateTime.parse(r['ends_at'] as String).toLocal(),
        repeatUntil: untilOf(r['rrule'] as String?),
        exdates: [for (final d in (r['exdates'] as List? ?? const [])) d as String],
        status: r['status'] as String,
        requesterId: r['requester_id'] as int?,
        requesterDisplay: r['requester_display'] as String? ?? '',
        ownerStaffId: r['owner_staff_id'] as int?,
        organizationId: r['organization_id'] as int?,
        attendees: r['attendees'] as int?,
        purpose: r['purpose'] as String? ?? '',
        publicNote: r['public_note'] as String? ?? '',
        contactLink: r['contact_link'] as String? ?? '',
      );

  int? id, requesterId, ownerStaffId, organizationId, attendees;
  String title, layer, kind, locationText, status, requesterDisplay, purpose, publicNote;
  final String contactLink; // from the "Book me" form; read-only here, so toRow() leaves it alone
  List<int> placeIds;
  List<String> exdates;
  DateTime start, end;
  DateTime? repeatUntil; // null = one-off

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'layer': layer,
        'kind': kind,
        'place_ids': placeIds,
        'location_text': _blank(locationText),
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
        'rrule': weeklyRrule(repeatUntil),
        'exdates': exdates,
        'status': status,
        'requester_id': requesterId,
        'requester_display': _blank(requesterDisplay),
        'owner_staff_id': ownerStaffId,
        'organization_id': organizationId,
        'attendees': attendees,
        'purpose': _blank(purpose),
        'public_note': _blank(publicNote),
      };

  /// Start of every occurrence: weekly until repeatUntil, minus the skipped dates.
  List<DateTime> occurrences() => repeatUntil == null
      ? [start]
      : [
          for (var d = start;
              !_day(d).isAfter(repeatUntil!);
              d = DateTime(d.year, d.month, d.day + 7, d.hour, d.minute))
            if (!exdates.contains(isoDate(d))) d
        ];

  String when() {
    final repeat = repeatUntil == null ? '' : ' · weekly until ${isoDate(repeatUntil!)}';
    return '${isoDate(start)} ${hhmm(start)}–${hhmm(end)}$repeat';
  }
}

int _min(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

/// Clash warnings for every occurrence of [a]: lessons in the same rooms (rows from `lessons`) and other
/// approved activities sharing a room. Warnings, not blocks: staff decide.
List<String> clashes(Activity a, Set<String> roomNames, List<Map<String, dynamic>> lessons, List<Activity> others) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final l in lessons) {
      final rooms = [for (final r in l['rooms'] as List) r as String].where(roomNames.contains);
      if (l['date'] == day && rooms.isNotEmpty && _min(l['start_time'] as String) < to && from < _min(l['end_time'] as String)) {
        out.add('$day ${(l['start_time'] as String).substring(0, 5)}–${(l['end_time'] as String).substring(0, 5)} '
            'lesson: ${l['course']} (${rooms.join(', ')})');
      }
    }
    for (final o in others) {
      if (o.id == a.id || !o.placeIds.any(a.placeIds.contains)) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} booking: ${o.title}');
        }
      }
    }
  }
  return out;
}

// ---------- inventory ----------

const movementKinds = ['receive', 'move', 'issue', 'return', 'consume', 'adjust'];

/// A `movements` row, checked against the same shape rule the database enforces (movement_shape).
/// Fields a kind doesn't use are sent as null, so the check constraint never trips on leftovers.
Map<String, dynamic> movementRow({
  required String kind,
  required int itemId,
  required num qty,
  int? from,
  int? to,
  int? personId,
  int? activityId,
  int? byStaff,
  int? assetId,
  String? note,
}) {
  var problem = switch (kind) {
    'receive' => to == null ? 'Pick where it goes.' : null,
    'move' => from == null || to == null ? 'Pick both places.' : (from == to ? 'From and to must differ.' : null),
    'issue' => from == null || personId == null ? 'Pick the place and the person.' : null,
    'return' => to == null || personId == null ? 'Pick the person and where it goes back.' : null,
    'consume' => from == null ? 'Pick where it was used from.' : null,
    'adjust' => to == null ? 'Pick the place to correct.' : null,
    _ => 'Unknown kind: $kind',
  };
  if (problem == null && kind == 'adjust' && qty == 0) problem = 'A correction of 0 changes nothing.';
  if (problem == null && kind != 'adjust' && qty <= 0) problem = 'Quantity must be more than 0.';
  if (problem == null && assetId != null && qty.abs() != 1) problem = 'A tagged item moves one at a time (quantity 1).';
  if (problem != null) throw ArgumentError(problem);
  return {
    'kind': kind,
    'item_id': itemId,
    'qty': qty,
    'from_place': const {'move', 'issue', 'consume'}.contains(kind) ? from : null,
    'to_place': const {'receive', 'move', 'return', 'adjust'}.contains(kind) ? to : null,
    'person_id': const {'issue', 'return'}.contains(kind) ? personId : null,
    'activity_id': activityId,
    'by_staff': byStaff,
    'asset_id': assetId,
    'note': note,
  };
}

/// Kit lines (item_id, qty) the place can't cover, as readable warnings. Stock rows: item_id, place_id, qty.
List<String> shortages(List<Map<String, dynamic>> kit, int placeId, List<Map<String, dynamic>> stock, Map<int, String> names) {
  num have(int item) => stock.where((s) => s['item_id'] == item && s['place_id'] == placeId).fold<num>(0, (t, s) => t + (s['qty'] as num));
  return [
    for (final k in kit)
      if (have(k['item_id'] as int) < (k['qty'] as num))
        '${names[k['item_id']] ?? 'item ${k['item_id']}'}: need ${k['qty']}, have ${have(k['item_id'] as int)}'
  ];
}

/// Stationary items (laser cutter, 3D printer…) that another approved activity has at an overlapping time.
List<String> equipmentClashes(Activity a, Set<int> mine, List<(Activity, Set<int>)> others, Map<int, String> names) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final (o, theirs) in others) {
      final shared = mine.intersection(theirs);
      if (o.id == a.id || shared.isEmpty) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} ${[for (final i in shared) names[i] ?? '$i'].join(', ')} '
              'also booked for ${o.title}');
        }
      }
    }
  }
  return out;
}

/// A TV carousel slide (tv_slides). The node applies the same date rule when it builds the playlist.
class TvSlide {
  TvSlide({
    this.id,
    this.kind = 'media',
    this.title = '',
    this.body = '',
    this.mediaName,
    this.url = '',
    this.seconds = 10,
    this.position = 0,
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.fromTime,
    this.toTime,
    this.fullscreen = false,
    this.takeover = false,
    this.activityId,
  });

  factory TvSlide.fromRow(Map<String, dynamic> r) => TvSlide(
        id: r['id'] as int?,
        kind: r['kind'] as String,
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        mediaName: r['media_name'] as String?,
        url: r['url'] as String? ?? '',
        seconds: r['seconds'] as int?,
        position: r['position'] as int? ?? 0,
        startsOn: r['starts_on'] == null ? null : DateTime.parse(r['starts_on'] as String),
        endsOn: r['ends_on'] == null ? null : DateTime.parse(r['ends_on'] as String),
        active: r['active'] as bool? ?? true,
        fromTime: (r['from_time'] as String?)?.substring(0, 5),
        toTime: (r['to_time'] as String?)?.substring(0, 5),
        fullscreen: r['fullscreen'] as bool? ?? false,
        takeover: r['takeover'] as bool? ?? false,
        activityId: r['activity_id'] as int?,
      );

  int? id;
  String kind, title, body, url;
  String? fromTime, toTime; // HH:MM, times of day the page plays; null: all day
  bool fullscreen, takeover; // takeover: while on, the TV plays only takeover pages
  int? activityId; // linked schedule event: the page plays in its time slot, its own dates and times are ignored
  String? mediaName;
  int? seconds; // null: play the video to its end
  int position;
  DateTime? startsOn, endsOn;
  bool active;

  Map<String, dynamic> toRow() => {
        'kind': kind,
        'title': _blank(title),
        'body': _blank(body),
        'media_name': mediaName,
        'url': _blank(url),
        'seconds': seconds,
        'position': position,
        'starts_on': startsOn == null ? null : isoDate(startsOn!),
        'ends_on': endsOn == null ? null : isoDate(endsOn!),
        'active': active,
        'from_time': fromTime,
        'to_time': toTime,
        'fullscreen': fullscreen,
        'takeover': takeover,
        'activity_id': activityId,
      };

  bool showsOn(DateTime day) {
    final d = isoDate(day);
    return active &&
        (startsOn == null || isoDate(startsOn!).compareTo(d) <= 0) &&
        (endsOn == null || isoDate(endsOn!).compareTo(d) >= 0);
  }

  /// The first thing to fix before saving, or null.
  String? problem() {
    if (kind == 'media' && mediaName == null) return 'Pick a file.';
    if ((kind == 'bio' || kind == 'text') && title.trim().isEmpty) {
      return kind == 'bio' ? 'Add a name.' : 'Add a title.';
    }
    if (kind == 'qr' && !RegExp(r'^https?://\S+$').hasMatch(url.trim())) {
      return 'The link must start with http:// or https://.';
    }
    if (seconds != null && seconds! < 1) return 'Seconds must be at least 1.';
    if (takeover && activityId == null && endsOn == null && toTime == null) {
      return 'A takeover needs an end: set "Until" (a date or a time), or it takes over the TV for good.';
    }
    if (fromTime != null && toTime != null && toTime!.compareTo(fromTime!) <= 0) {
      return 'The end time is before the start time.';
    }
    if (startsOn != null && endsOn != null && endsOn!.isBefore(startsOn!)) {
      return 'The end date is before the start date.';
    }
    return null;
  }
}

/// The office's line about the TV, from the node's heartbeat (tv_status): what it plays, or why it is stale.
/// ok is false when the last build is more than 5 minutes old, never happened, or the last run failed.
({String text, bool ok}) tvStatusLine(Map<String, dynamic>? r, DateTime now) {
  String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final built = r?['built_at'] == null ? null : DateTime.parse(r!['built_at'] as String).toLocal();
  final errorAt = r?['error_at'] == null ? null : DateTime.parse(r!['error_at'] as String).toLocal();
  if (built == null) return (text: 'TV: the lab node has not built a playlist yet.${r?['error'] == null ? '' : ' ${r!['error']}'}', ok: false);
  final failing = errorAt != null && errorAt.isAfter(built);
  if (failing || now.difference(built).inMinutes >= 5) {
    return (text: 'TV not updating since ${hm(built)}${failing ? ': ${r!['error']}' : ': is the lab node on?'}', ok: false);
  }
  return (
    text: '${r!['playing'] ?? 'TV playlist built'} · built ${hm(built)} · ${r['media']} files',
    ok: true,
  );
}

/// Warnings per slide id, for the office list: takeover pages whose dates and times overlap, and pages that use the same file.
/// (Drafted by a local model, Qwen3-Coder on Unsloth Studio, then corrected.)
Map<int, String> tvWarnings(List<TvSlide> slides) {
  final on = [for (final s in slides) if (s.active && s.id != null) s];
  String name(TvSlide s) => s.title.isNotEmpty ? s.title : s.mediaName ?? s.kind;
  String day(DateTime? d, String open) => d == null ? open : isoDate(d);
  bool overlap(TvSlide a, TvSlide b) =>
      a.takeover &&
      b.takeover &&
      day(a.startsOn, '0000-01-01').compareTo(day(b.endsOn, '9999-12-31')) <= 0 &&
      day(b.startsOn, '0000-01-01').compareTo(day(a.endsOn, '9999-12-31')) <= 0 &&
      (a.fromTime ?? '00:00').compareTo(b.toTime ?? '24:00') < 0 &&
      (b.fromTime ?? '00:00').compareTo(a.toTime ?? '24:00') < 0;
  return {
    for (final s in on)
      if ([
        for (final o in on) if (o != s && overlap(s, o)) 'overlaps takeover "${name(o)}"',
        for (final o in on) if (o != s && s.mediaName != null && o.mediaName == s.mediaName) 'same file as "${name(o)}"',
      ] case final m when m.isNotEmpty)
        s.id!: m.join('; '),
  };
}

// ---------- smart storage ----------

final _code = RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$');

/// Place codes are capitals, digits and dashes (R15-L-S3): the database's check, before the round trip.
bool validCode(String code) => _code.hasMatch(code);

/// Places parents first, each with its depth; siblings by code, then name. A place whose parent is missing is a root.
List<(Map<String, dynamic>, int)> placeTree(List<Map<String, dynamic>> places) {
  final ids = {for (final p in places) p['id']};
  final kids = <Object?, List<Map<String, dynamic>>>{};
  for (final p in places) {
    kids.putIfAbsent(ids.contains(p['parent_id']) ? p['parent_id'] : null, () => []).add(p);
  }
  String key(Map<String, dynamic> p) => '${p['code'] ?? '~'} ${p['name']}';
  final out = <(Map<String, dynamic>, int)>[];
  final seen = <Object?>{};
  void walk(Object? parent, int depth) {
    for (final p in (kids[parent] ?? <Map<String, dynamic>>[])..sort((a, b) => key(a).compareTo(key(b)))) {
      if (!seen.add(p['id'])) continue;
      out.add((p, depth));
      walk(p['id'], depth + 1);
    }
  }

  walk(null, 0);
  // a parent loop: show those places at the top rather than lose them
  out.addAll([for (final p in places) if (!seen.contains(p['id'])) (p, 0)]);
  return out;
}

/// Stocktake: one 'adjust' row per counted item whose count differs from what the place should hold.
/// expected and counted map item id -> quantity (untagged only; tagged items are ticked one by one).
List<Map<String, dynamic>> countAdjustments(Map<int, num> expected, Map<int, num> counted, int placeId, {int? byStaff}) => [
      for (final e in counted.entries)
        if (e.value != (expected[e.key] ?? 0))
          movementRow(kind: 'adjust', itemId: e.key, qty: e.value - (expected[e.key] ?? 0), to: placeId, byStaff: byStaff, note: 'stocktake')
    ];
```

- [ ] **Step 2 (pi): replace `apps/office/test/logic_test.dart`**

```dart
// Run: flutter test (from apps/office)
import 'package:flutter_test/flutter_test.dart';
import 'package:office/logic.dart';

void main() {
  test('weekly rrule round-trips its until date in the local form the export reads', () {
    expect(weeklyRrule(null), isNull);
    expect(weeklyRrule(DateTime(2026, 12, 31)), 'FREQ=WEEKLY;UNTIL=20261231T235959');
    expect(untilOf('FREQ=WEEKLY;UNTIL=20261231T235959'), DateTime(2026, 12, 31));
    expect(untilOf(null), isNull);
  });

  test('occurrences: weekly until the date, minus skipped dates, wall clock kept across DST', () {
    final a = Activity(
      start: DateTime(2026, 10, 20, 17),
      end: DateTime(2026, 10, 20, 19),
      repeatUntil: DateTime(2026, 11, 3),
      exdates: ['2026-10-27'],
    );
    expect([for (final d in a.occurrences()) '${isoDate(d)} ${hhmm(d)}'], ['2026-10-20 17:00', '2026-11-03 17:00']);
    expect(Activity(start: DateTime(2026, 10, 20, 17), end: DateTime(2026, 10, 20, 18)).occurrences().length, 1);
  });

  test('row mapping: blanks become null, times go out as UTC, round trip keeps fields', () {
    final a = Activity(
      title: ' Club ',
      kind: 'club',
      placeIds: [1],
      start: DateTime(2026, 10, 20, 17),
      end: DateTime(2026, 10, 20, 19),
      repeatUntil: DateTime(2026, 12, 15),
      requesterDisplay: '  ',
      purpose: 'robots',
    );
    final row = a.toRow();
    expect(row['title'], 'Club');
    expect(row['requester_display'], isNull);
    expect(row['location_text'], isNull);
    expect((row['starts_at'] as String).endsWith('Z'), isTrue);
    final b = Activity.fromRow({...row, 'id': 5, 'exdates': <String>[]});
    expect([b.id, b.title, b.kind, b.placeIds, b.start, b.end, b.repeatUntil, b.purpose],
        [5, 'Club', 'club', [1], a.start, a.end, a.repeatUntil, 'robots']);
  });

  test('clashes: lessons in the same room and approved bookings sharing a room, only when times overlap', () {
    final a = Activity(id: 1, title: 'Class', placeIds: [1], start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12));
    final lessons = [
      {'date': '2026-10-20', 'start_time': '11:00:00', 'end_time': '13:00:00', 'course': 'Maths', 'rooms': ['Tech Lab']},
      {'date': '2026-10-20', 'start_time': '12:00:00', 'end_time': '13:00:00', 'course': 'Touching', 'rooms': ['Tech Lab']},
      {'date': '2026-10-20', 'start_time': '10:00:00', 'end_time': '11:00:00', 'course': 'Elsewhere', 'rooms': ['Sala 1']},
    ];
    final others = [
      Activity(id: 2, title: 'Club', placeIds: [1], start: DateTime(2026, 10, 20, 9), end: DateTime(2026, 10, 20, 10, 30)),
      Activity(id: 3, title: 'Other room', placeIds: [2], start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12)),
    ];
    expect(clashes(a, {'Tech Lab'}, lessons, others), [
      '2026-10-20 11:00–13:00 lesson: Maths (Tech Lab)',
      '2026-10-20 09:00–10:30 booking: Club',
    ]);
  });

  test('movement rows follow the database shape rule and null the fields a kind does not use', () {
    expect(movementRow(kind: 'receive', itemId: 1, qty: 10, from: 3, to: 2),
        {
          'kind': 'receive', 'item_id': 1, 'qty': 10, 'from_place': null, 'to_place': 2, 'person_id': null, 'activity_id': null, 'by_staff': null,
          'asset_id': null, 'note': null,
        });
    expect(movementRow(kind: 'issue', itemId: 1, qty: 1, from: 2, personId: 7, assetId: 40)['asset_id'], 40);
    expect(() => movementRow(kind: 'receive', itemId: 1, qty: 2, to: 2, assetId: 40), throwsArgumentError);
    expect(movementRow(kind: 'issue', itemId: 1, qty: 2, from: 2, to: 9, personId: 7, activityId: 5)['to_place'], isNull);
    expect(movementRow(kind: 'adjust', itemId: 1, qty: -3, to: 2)['qty'], -3);
    for (final bad in [
      () => movementRow(kind: 'issue', itemId: 1, qty: 2, from: 2),
      () => movementRow(kind: 'move', itemId: 1, qty: 2, from: 2, to: 2),
      () => movementRow(kind: 'receive', itemId: 1, qty: 0, to: 2),
      () => movementRow(kind: 'adjust', itemId: 1, qty: 0, to: 2),
      () => movementRow(kind: 'teleport', itemId: 1, qty: 1, to: 2),
    ]) {
      expect(bad, throwsArgumentError);
    }
  });

  test('shortages: kit lines the chosen place cannot cover', () {
    final stock = [
      {'item_id': 1, 'place_id': 2, 'qty': 3},
      {'item_id': 1, 'place_id': 9, 'qty': 50},
      {'item_id': 4, 'place_id': 2, 'qty': 8},
    ];
    final kit = [
      {'item_id': 1, 'qty': 5},
      {'item_id': 4, 'qty': 8},
      {'item_id': 6, 'qty': 1},
    ];
    expect(shortages(kit, 2, stock, {1: 'ESP32', 4: 'Breadboard'}), ['ESP32: need 5, have 3', 'item 6: need 1, have 0']);
  });

  test('stationary equipment booked twice at overlapping times', () {
    final a = Activity(id: 1, title: 'Workshop', start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12));
    final others = [
      (Activity(id: 2, title: 'Club', start: DateTime(2026, 10, 20, 11), end: DateTime(2026, 10, 20, 13)), {7}),
      (Activity(id: 3, title: 'Later', start: DateTime(2026, 10, 20, 12), end: DateTime(2026, 10, 20, 13)), {7}),
      (Activity(id: 4, title: 'Other kit', start: DateTime(2026, 10, 20, 10), end: DateTime(2026, 10, 20, 12)), {8}),
    ];
    expect(equipmentClashes(a, {7}, others, {7: 'Laser cutter'}), ['2026-10-20 11:00–13:00 Laser cutter also booked for Club']);
  });

  test('the student link from "Book me" is read, never written back by staff saves', () {
    final a = Activity.fromRow({
      'id': 9, 'title': 'Consultation', 'layer': 'booking', 'kind': 'consultation', 'place_ids': [1],
      'starts_at': '2026-10-06T13:00:00Z', 'ends_at': '2026-10-06T13:30:00Z', 'status': 'requested',
      'contact_link': 'https://github.com/ana', 'purpose': 'Robot arm',
    });
    expect(a.contactLink, 'https://github.com/ana');
    expect(a.toRow().containsKey('contact_link'), isFalse);
    expect(a.toRow().containsKey('status_token'), isFalse);
  });

  test('TV warnings: overlapping takeovers and the same file twice', () {
    final a = TvSlide(id: 1, kind: 'media', title: 'PROTO26', mediaName: 'proto.mp4', startsOn: DateTime(2026, 9, 25),
        endsOn: DateTime(2026, 9, 25), fromTime: '17:00', toTime: '20:00', takeover: true);
    final b = TvSlide(id: 2, kind: 'media', title: 'PROTO26 copy', mediaName: 'proto.mp4', takeover: true); // no window: always
    final c = TvSlide(id: 3, kind: 'text', title: 'Late', fromTime: '20:00', toTime: '22:00', takeover: true);
    final d = TvSlide(id: 4, kind: 'text', title: 'Off', takeover: true, active: false);
    final e = TvSlide(id: 5, kind: 'text', title: 'Tomorrow', startsOn: DateTime(2026, 9, 26), endsOn: DateTime(2026, 9, 26), takeover: true);
    final w = tvWarnings([a, b, c, d]);
    expect(w[1], 'overlaps takeover "PROTO26 copy"; same file as "PROTO26 copy"');
    expect(w[2], 'overlaps takeover "PROTO26"; overlaps takeover "Late"; same file as "PROTO26"');
    expect(w[3], 'overlaps takeover "PROTO26 copy"', reason: '20:00 end and 20:00 start do not overlap');
    expect(w.containsKey(4), isFalse, reason: 'a page that is off is ignored');
    expect(tvWarnings([a, e]), isEmpty, reason: 'different days');
    expect(tvWarnings([a]), isEmpty);
  });

  test('TV status line from the node heartbeat', () {
    final now = DateTime.parse('2026-09-25T14:03:00Z');
    final good = {'built_at': '2026-09-25T14:02:00Z', 'pages': 1, 'media': 2, 'takeover': true, 'error': null, 'error_at': null,
      'playing': 'Takeover: PROTO26 until 20:00'};
    expect(tvStatusLine(good, now).ok, isTrue);
    expect(tvStatusLine(good, now).text, startsWith('Takeover: PROTO26 until 20:00 · built '));
    expect(tvStatusLine(good, DateTime.parse('2026-09-25T14:10:00Z')).ok, isFalse, reason: 'stale after 5 minutes');
    final failing = {...good, 'error': 'OSError: disk full', 'error_at': '2026-09-25T14:02:30Z'};
    expect(tvStatusLine(failing, now).text, contains('disk full'));
    expect(tvStatusLine(failing, now).ok, isFalse);
    expect(tvStatusLine(null, now).ok, isFalse);
  });

  test('TV slide: row round trip, date window, problems', () {
    final s = TvSlide.fromRow({
      'id': 3, 'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
      'from_time': '17:00:00', 'to_time': '20:00:00', 'fullscreen': true, 'takeover': true,
    });
    expect(s.toRow(), {
      'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
      'from_time': '17:00', 'to_time': '20:00', 'fullscreen': true, 'takeover': true, 'activity_id': null,
    });
    expect(TvSlide(kind: 'text', title: 'x', fromTime: '20:00', toTime: '17:00').problem(), contains('end time'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true).problem(), contains('needs an end'));
    expect(TvSlide(kind: 'text', title: 'x', takeover: true, toTime: '20:00').problem(), isNull);
    expect(TvSlide(kind: 'text', title: 'x', takeover: true, activityId: 56).problem(), isNull, reason: 'the event gives the end');
    expect(TvSlide.fromRow({'id': 1, 'kind': 'text', 'activity_id': 56}).toRow()['activity_id'], 56);
    expect(s.showsOn(DateTime(2026, 10, 1)), isTrue);
    expect(s.showsOn(DateTime(2026, 11, 1)), isFalse);
    expect((s..active = false).showsOn(DateTime(2026, 10, 5)), isFalse);
    expect(s.problem(), isNull);
    expect(TvSlide(kind: 'qr', title: 'x', url: 'instagram.com').problem(), contains('http'));
    expect(TvSlide(kind: 'media').problem(), contains('file'));
    expect(TvSlide(kind: 'text', title: 'x', seconds: 0).problem(), contains('Seconds'));
    final whole = TvSlide.fromRow({'id': 4, 'kind': 'media', 'media_name': 'reel.m4v', 'seconds': null});
    expect(whole.seconds, isNull, reason: 'empty seconds: the whole video');
    expect(whole.toRow()['seconds'], isNull);
    expect(whole.problem(), isNull);
    expect(TvSlide(kind: 'bio').problem(), contains('name'));
    expect(TvSlide(kind: 'text', title: 'x', startsOn: DateTime(2026, 10, 2), endsOn: DateTime(2026, 10, 1)).problem(),
        contains('end date'));
  });

  test('place codes follow the database rule', () {
    for (final ok in ['R15', 'R15-L-S3', 'B2-R1-S4', 'CUP1']) {
      expect(validCode(ok), isTrue, reason: ok);
    }
    for (final bad in ['r15', 'R15 L', 'R15--L', '-R15', 'R15-', '']) {
      expect(validCode(bad), isFalse, reason: bad);
    }
  });

  test('place tree: parents first with depth, siblings by code, orphans and loops kept', () {
    final places = [
      {'id': 3, 'code': 'R15-L-S1', 'name': 'Shelf 1', 'parent_id': 2},
      {'id': 2, 'code': 'R15-L', 'name': 'Left', 'parent_id': 1},
      {'id': 1, 'code': 'R15', 'name': 'Room 15', 'parent_id': null},
      {'id': 4, 'code': 'B2', 'name': '-2 floor', 'parent_id': null},
      {'id': 5, 'code': null, 'name': 'Orphan', 'parent_id': 99},
      {'id': 6, 'code': 'X', 'name': 'Loop a', 'parent_id': 7},
      {'id': 7, 'code': 'Y', 'name': 'Loop b', 'parent_id': 6},
    ];
    expect([for (final (p, d) in placeTree(places)) '${p['id']}:$d'], ['4:0', '1:0', '2:1', '3:2', '5:0', '6:0', '7:0']);
  });

  test('stocktake: adjust rows for the differences only, marked as stocktake', () {
    final rows = countAdjustments({1: 10, 2: 4}, {1: 8, 2: 4, 3: 1}, 9, byStaff: 5);
    expect([for (final r in rows) '${r['item_id']}:${r['qty']}'], ['1:-2', '3:1']);
    expect(rows.first['kind'], 'adjust');
    expect(rows.first['to_place'], 9);
    expect(rows.first['note'], 'stocktake');
    expect(rows.first['by_staff'], 5);
  });
}
```

- [ ] **Step 3 (pi): replace `apps/office/lib/data.dart`**

```dart
// Every query the office makes. RLS lets only staff (people.is_staff, linked by auth_user_id) read or write.
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logic.dart';

SupabaseClient get db => Supabase.instance.client;

/// Gives up after 20 s instead of leaving a spinner forever (lesson from UNIDCOM RIMS).
class TimeoutClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 20));
}

typedef Rec = Map<String, dynamic>;

/// Reference lists the pages need, loaded once per page.
class Refs {
  Refs(this.places, this.people, this.orgs, this.items, this.assets, this.me);
  final List<Rec> places, people, orgs, items, assets;
  final int? me; // the signed-in staff member's people.id
  List<Rec> get rooms => [for (final p in places) if (p['kind'] == 'room') p];
  Map<int, String> get itemNames => {for (final i in items) i['id'] as int: i['name'] as String};
  Rec? placeByCode(String code) => places.where((p) => p['code'] == code).firstOrNull;
  String placeName(int? id) {
    final p = places.where((p) => p['id'] == id).firstOrNull;
    return p == null ? '?' : (p['code'] == null ? p['name'] as String : '${p['code']} · ${p['name']}');
  }
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select(placeCols).order('name'),
    db.from('people').select('id,name,kind,email').order('name'),
    db.from('organizations').select('id,name').order('name'),
    db.from('items').select('id,name,kind,note').isFilter('merged_into', null).order('name'),
    db.from('assets').select('id,item_id,tag,serial,condition').order('tag'),
    db.from('people').select('id').eq('auth_user_id', db.auth.currentUser!.id).maybeSingle(),
  ]);
  return Refs(r[0] as List<Rec>, r[1] as List<Rec>, r[2] as List<Rec>, r[3] as List<Rec>, r[4] as List<Rec>, (r[5] as Rec?)?['id'] as int?);
}

const placeCols = 'id,name,iade_name,kind,tier,parent_id,code,counted_at';

/// Upcoming activities, plus repeating ones that started earlier.
Future<List<Activity>> upcoming() async {
  final since = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
  final rows = await db.from('activities').select().or('ends_at.gte.$since,rrule.not.is.null').order('starts_at');
  return [for (final r in rows) Activity.fromRow(r)];
}

Future<int> saveActivity(Activity a) async {
  if (a.id != null) {
    await db.from('activities').update(a.toRow()).eq('id', a.id!);
    return a.id!;
  }
  return (await db.from('activities').insert(a.toRow()).select('id').single())['id'] as int;
}

Future<List<String>> clashWarnings(Activity a, Refs refs) async {
  if (a.placeIds.isEmpty) return _stationaryClashes(a, refs);
  final names = {
    for (final r in refs.rooms)
      if (a.placeIds.contains(r['id'])) (r['iade_name'] ?? r['name']) as String
  };
  final last = a.occurrences().last;
  final lessons = await db
      .from('lessons')
      .select('date,start_time,end_time,course,rooms')
      .gte('date', isoDate(a.start))
      .lte('date', isoDate(last))
      .overlaps('rooms', names.toList());
  final others = await db.from('activities').select().eq('status', 'approved').overlaps('place_ids', a.placeIds);
  return [...clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]), ...await _stationaryClashes(a, refs)];
}

/// The same laser cutter / printer booked by another approved activity at an overlapping time.
Future<List<String>> _stationaryClashes(Activity a, Refs refs) async {
  if (a.id == null) return [];
  final mine = {
    for (final k in await equipment(a.id!))
      if ((k['items'] as Rec)['kind'] == 'stationary') k['item_id'] as int
  };
  if (mine.isEmpty) return [];
  final rows = await db
      .from('activity_items')
      .select('item_id,activities!inner(*)')
      .inFilter('item_id', mine.toList())
      .eq('activities.status', 'approved')
      .neq('activity_id', a.id!);
  final byActivity = <int, (Activity, Set<int>)>{};
  for (final r in rows) {
    final o = Activity.fromRow(r['activities'] as Rec);
    byActivity.putIfAbsent(o.id!, () => (o, <int>{})).$2.add(r['item_id'] as int);
  }
  return equipmentClashes(a, mine, byActivity.values.toList(), refs.itemNames);
}

Future<List<Rec>> equipment(int activityId) =>
    db.from('activity_items').select('item_id,qty,prepared,items(name,kind)').eq('activity_id', activityId).order('item_id');

Future<void> setEquipment(int activityId, int itemId, num qty, bool prepared) => db
    .from('activity_items')
    .upsert({'activity_id': activityId, 'item_id': itemId, 'qty': qty, 'prepared': prepared});

Future<void> removeEquipment(int activityId, int itemId) =>
    db.from('activity_items').delete().eq('activity_id', activityId).eq('item_id', itemId);

Future<Rec> addPerson(String name, String kind, String email) => db
    .from('people')
    .insert({'name': name.trim(), 'kind': kind, 'email': email.trim().isEmpty ? null : email.trim().toLowerCase()})
    .select('id,name,kind,email')
    .single();

Future<Rec> addItem(String name, String kind) =>
    db.from('items').insert({'name': name.trim(), 'kind': kind}).select('id,name,kind').single();

// ---------- inventory ----------

Future<List<Rec>> stock() => db.from('stock').select('item_id,place_id,qty');

Future<List<Rec>> onLoan() => db.from('on_loan').select('item_id,person_id,qty');

/// Movements are append-only: a mistake is corrected with an 'adjust' row, never edited.
Future<void> addMovements(List<Rec> rows) => db.from('movements').insert(rows);

// ---------- smart storage ----------

/// Where each tagged item is now (its latest movement): place_id, or person_id while on loan.
Future<List<Rec>> assetPlaces() => db.from('asset_place').select('asset_id,place_id,person_id');

/// Everything in Needs attention (view storage_issues), waived ones already left out.
Future<List<Rec>> storageIssues() => db.from('storage_issues').select('code,a_id,b_id,detail,key').order('code').order('detail');

Future<Rec> savePlace(Rec row, int? id) => id == null
    ? db.from('places').insert(row).select(placeCols).single()
    : db.from('places').update(row).eq('id', id).select(placeCols).single();

Future<void> markCounted(int placeId) =>
    db.from('places').update({'counted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', placeId);

Future<Rec> addAsset(int itemId, String tag, String serial) => db
    .from('assets')
    .insert({'item_id': itemId, if (tag.trim().isNotEmpty) 'tag': tag.trim(), 'serial': serial.trim().isEmpty ? null : serial.trim()})
    .select('id,item_id,tag,serial,condition')
    .single();

Future<void> updateAssets(List<int> ids, Rec change) => db.from('assets').update(change).inFilter('id', ids);

Future<void> waiveIssue(String key, int? staffId) => db.from('issue_waivers').insert({'key': key, 'by_staff': staffId});

/// Soft merge (merge_items): the losers' stock, tagged items and kit lines move to the survivor; the losers stay, hidden.
Future<void> mergeItems(int survivor, List<int> losers) => db.rpc('merge_items', params: {'p_survivor': survivor, 'p_losers': losers});

// ---------- book me ----------

Future<List<Rec>> consultationHours() =>
    db.from('consultation_hours').select('id,weekday,from_time,to_time,slot_minutes,places(name),people(name)').order('weekday').order('from_time');

Future<void> addConsultationHours(int staffId, int placeId, int weekday, String from, String to, int slotMinutes) => db
    .from('consultation_hours')
    .insert({'staff_id': staffId, 'place_id': placeId, 'weekday': weekday, 'from_time': from, 'to_time': to, 'slot_minutes': slotMinutes});

Future<void> removeConsultationHours(int id) => db.from('consultation_hours').delete().eq('id', id);

/// Everything a person asked for before: their lab history, newest first.
Future<List<Rec>> history(int personId) => db
    .from('activities')
    .select('id,title,kind,status,starts_at,purpose,contact_link')
    .eq('requester_id', personId)
    .order('starts_at', ascending: false)
    .limit(50);

// ---------- idea hub ----------

Future<List<Rec>> ideas(String status) => db
    .from('ideas')
    .select('id,body,status,workshop,created_at,ai_title,ai_keywords,people(name)')
    .eq('status', status)
    .order('created_at', ascending: false);

Future<Rec> idea1(int id) => db
    .from('ideas')
    .select('id,person_id,body,link,can_bring,looking_for,status,workshop,created_at,ai_title,ai_summary,ai_keywords,ai_model,ai_done_at,'
        'people(name,email,student_number)')
    .eq('id', id)
    .single();

Future<void> updateIdea(int id, Rec change) => db.from('ideas').update(change).eq('id', id);

Future<List<Rec>> ideaMatches(int id) => db
    .from('idea_matches')
    .select('idea_a,idea_b,kind,score,reason,a_connect,b_connect,'
        'a:ideas!idea_matches_idea_a_fkey(id,ai_title,people(name)),b:ideas!idea_matches_idea_b_fkey(id,ai_title,people(name))')
    .or('idea_a.eq.$id,idea_b.eq.$id')
    .order('score', ascending: false);

Future<List<Rec>> personIdeas(int personId) =>
    db.from('ideas').select('id,status,created_at,ai_title,body').eq('person_id', personId).order('created_at', ascending: false);

Future<List<TvSlide>> tvSlides() async =>
    [for (final r in await db.from('tv_slides').select().order('position').order('id')) TvSlide.fromRow(r)];

/// Approved events and bookings from yesterday on, to link TV pages to.
Future<List<Rec>> tvEvents() async => await db
    .from('activities')
    .select('id,title,layer,starts_at,ends_at')
    .eq('status', 'approved')
    .gte('ends_at', DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String())
    .order('starts_at')
    .limit(100);

/// The edge node's heartbeat for the TV (one row), or null before its first run.
Future<Rec?> tvStatus() async => await db.from('tv_status').select().maybeSingle();

/// The files the edge node reported from its shared TV folder.
Future<List<Rec>> tvMedia() async => await db.from('tv_media').select('name,kind,playable,seconds').order('name');

Future<void> saveTvSlide(TvSlide s) async {
  if (s.id == null) {
    await db.from('tv_slides').insert(s.toRow());
  } else {
    await db.from('tv_slides').update(s.toRow()).eq('id', s.id!);
  }
}

Future<void> deleteTvSlide(int id) async => await db.from('tv_slides').delete().eq('id', id);

Future<void> reorderTvSlides(List<int> ids) async =>
    await Future.wait([for (var i = 0; i < ids.length; i++) db.from('tv_slides').update({'position': i}).eq('id', ids[i])]);
```

- [ ] **Step 4 (pi): replace `apps/office/lib/inventory.dart`**

```dart
// Inventory: Needs attention, stock per place, who holds what, and one form for every movement.
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';
import 'places.dart';

void say(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The Record movement form. `placeId` prefills From or To (a place's own screen). True when something was recorded.
Future<bool> recordMovement(BuildContext context, Refs refs, {int? placeId}) async {
  var kind = 'receive';
  int? itemId, assetId, from = placeId, to = placeId, personId;
  final qty = TextEditingController(text: '1');
  final newName = TextEditingController();
  var newKind = 'portable';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        DropdownButton<int?> placePick(String hint, int? value, void Function(int?) change) => DropdownButton<int?>(
          value: value,
          isExpanded: true,
          hint: Text(hint),
          items: [
            for (final (p, depth) in placeTree(refs.places))
              DropdownMenuItem(value: p['id'] as int, child: Text('${'  ' * depth}${refs.placeName(p['id'] as int)}')),
          ],
          onChanged: (v) => set(() => change(v)),
        );
        final tagged = [
          for (final a in refs.assets)
            if (a['item_id'] == itemId) a,
        ];
        return AlertDialog(
          title: const Text('Record movement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: kind,
                  isExpanded: true,
                  items: [for (final k in movementKinds) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => set(() => kind = v!),
                ),
                DropdownButton<int?>(
                  value: itemId,
                  isExpanded: true,
                  hint: const Text('Item, or type a new one below'),
                  items: [for (final i in refs.items) DropdownMenuItem(value: i['id'] as int, child: Text('${i['name']} (${i['kind']})'))],
                  onChanged: (v) => set(() => (itemId, assetId) = (v, null)),
                ),
                if (itemId == null) ...[
                  TextField(
                    controller: newName,
                    decoration: const InputDecoration(labelText: 'New item name'),
                  ),
                  DropdownButton<String>(
                    value: newKind,
                    isExpanded: true,
                    items: [
                      for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) => set(() => newKind = v!),
                  ),
                ],
                if (tagged.isNotEmpty)
                  DropdownButton<int?>(
                    value: assetId,
                    isExpanded: true,
                    hint: const Text('Tagged one (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Untagged')),
                      for (final a in tagged)
                        DropdownMenuItem(
                          value: a['id'] as int,
                          child: Text('${a['tag']}${a['serial'] == null ? '' : ' · ${a['serial']}'}'),
                        ),
                    ],
                    onChanged: (v) => set(() {
                      assetId = v;
                      if (v != null) qty.text = kind == 'adjust' && qty.text.startsWith('-') ? '-1' : '1';
                    }),
                  ),
                TextField(
                  controller: qty,
                  decoration: InputDecoration(labelText: kind == 'adjust' ? 'Correction (+/-)' : 'Quantity'),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                ),
                if (const {'move', 'issue', 'consume'}.contains(kind)) placePick('From', from, (v) => from = v),
                if (const {'receive', 'move', 'return', 'adjust'}.contains(kind))
                  placePick(kind == 'adjust' ? 'Place' : 'To', to, (v) => to = v),
                if (const {'issue', 'return'}.contains(kind))
                  DropdownButton<int?>(
                    value: personId,
                    isExpanded: true,
                    hint: Text(kind == 'issue' ? 'Given to' : 'Returned by'),
                    items: [
                      for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (${p['kind']})')),
                    ],
                    onChanged: (v) => set(() => personId = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    if (itemId == null) {
      if (newName.text.trim().isEmpty) {
        say(context, 'Pick an item or type a new one.');
        return false;
      }
      final item = await addItem(newName.text, newKind);
      refs.items.add(item);
      itemId = item['id'] as int;
    }
    final row = movementRow(
      kind: kind,
      itemId: itemId!,
      qty: num.tryParse(qty.text.trim()) ?? 0,
      from: from,
      to: to,
      personId: personId,
      byStaff: refs.me,
      assetId: assetId,
    );
    await addMovements([row]);
    if (context.mounted) say(context, 'Recorded: $kind ${row['qty']} × ${refs.itemNames[itemId]}.');
    return true;
  } on ArgumentError catch (e) {
    if (context.mounted) say(context, e.message as String);
  } catch (e) {
    if (context.mounted) say(context, 'Could not record: $e');
  }
  return false;
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final refs = widget.refs;
  late Future<(List<Rec>, List<Rec>, List<Rec>)> data = _load();

  Future<(List<Rec>, List<Rec>, List<Rec>)> _load() async => (await stock(), await onLoan(), await storageIssues());

  String _person(int? id) => refs.people.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;

  void _reload() => setState(() => data = _load());

  Future<void> _merge(Rec issue) async {
    final a = issue['a_id'] as int, b = issue['b_id'] as int;
    final keep = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Same thing? Keep which name'),
        children: [
          for (final id in [a, b])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text(refs.itemNames[id] ?? 'item $id')),
        ],
      ),
    );
    if (keep == null) return;
    try {
      await mergeItems(keep, [keep == a ? b : a]);
      refs.items.removeWhere((i) => i['id'] == (keep == a ? b : a));
      for (final x in refs.assets) {
        if (x['item_id'] == (keep == a ? b : a)) x['item_id'] = keep;
      }
      if (mounted) say(context, 'Merged into ${refs.itemNames[keep]}.');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not merge: $e');
    }
  }

  Future<void> _waive(Rec issue) async {
    try {
      await waiveIssue(issue['key'] as String, refs.me);
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not dismiss: $e');
    }
  }

  Widget _issue(Rec i) {
    final code = i['code'] as String;
    final placeIssue = code == 'never_counted' || code == 'stale_count';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.error_outline, color: Colors.orange),
      title: Text(i['detail'] as String),
      subtitle: Text(code.replaceAll('_', ' ')),
      onTap: placeIssue
          ? () async {
              final p = refs.places.where((p) => p['id'] == i['a_id']).firstOrNull;
              if (p == null) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlacePage(refs: refs, place: p),
                ),
              );
              _reload();
            }
          : null,
      trailing: Wrap(
        children: [
          if (code == 'possible_duplicate') TextButton(onPressed: () => _merge(i), child: const Text('Merge')),
          TextButton(onPressed: () => _waive(i), child: Text(code == 'possible_duplicate' ? 'Not the same' : 'Dismiss')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Inventory'),
      actions: [
        IconButton(
          tooltip: 'Places',
          icon: const Icon(Icons.account_tree_outlined),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlacesPage(refs: refs)));
            _reload();
          },
        ),
        IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        if (await recordMovement(context, refs)) _reload();
      },
      icon: const Icon(Icons.swap_horiz),
      label: const Text('Record movement'),
    ),
    body: FutureBuilder(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        final loaded = snap.data;
        if (loaded == null) return const Center(child: CircularProgressIndicator());
        final (stockRows, loans, issues) = loaded;
        if (refs.items.isEmpty) return const Center(child: Text('No items yet. Record a "receive" to add the first one.'));
        return ListView(
          children: [
            if (issues.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: issues.length <= 10,
                leading: const Icon(Icons.warning_amber),
                title: Text('Needs attention (${issues.length})'),
                children: [for (final i in issues) _issue(i)],
              ),
            for (final i in refs.items)
              Builder(
                builder: (context) {
                  final here = [
                    for (final s in stockRows)
                      if (s['item_id'] == i['id'] && s['qty'] != 0) s,
                  ];
                  final out = [
                    for (final l in loans)
                      if (l['item_id'] == i['id']) l,
                  ];
                  final total = here.fold<num>(0, (t, s) => t + (s['qty'] as num));
                  final tags = refs.assets.where((a) => a['item_id'] == i['id']).length;
                  return ListTile(
                    title: Text('${i['name']} (${i['kind']})${tags == 0 ? '' : ' · $tags tagged'}'),
                    subtitle: Text(
                      [
                        for (final s in here) '${refs.placeName(s['place_id'] as int?)} ${s['qty']}',
                        for (final l in out) 'on loan: ${_person(l['person_id'] as int?)} ${l['qty']}',
                      ].join(' · '),
                    ),
                    trailing: Text('$total', style: Theme.of(context).textTheme.titleMedium),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}
```

- [ ] **Step 5 (pi): create `apps/office/lib/places.dart`**

```dart
// Places: the storage tree (rooms, cabinets, shelves, boxes), each place's contents, and the stocktake.
// A place's code is on its QR label (office/?place=CODE) and is the node name in the Godot twin: keep it once printed.
import 'package:flutter/material.dart';

import 'bookings.dart';
import 'data.dart';
import 'inventory.dart';
import 'logic.dart';

String _day(Object? at) => at == null ? 'never counted' : 'counted ${isoDate(DateTime.parse(at as String).toLocal())}';

/// Add a place (parent given) or edit one. Returns the saved row.
Future<Rec?> editPlace(BuildContext context, Refs refs, {Rec? place, int? parentId}) async {
  final name = TextEditingController(text: place?['name'] as String? ?? '');
  final code = TextEditingController(text: place?['code'] as String? ?? '');
  var tier = place?['tier'] as String? ?? 'fast';
  int? parent = place == null ? parentId : place['parent_id'] as int?;
  final isRoom = place?['kind'] == 'room';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: Text(place == null ? 'Add place' : 'Edit place'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (e.g. Rack 1, shelf 2)'),
              ),
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Code (e.g. B2-R1-S2)',
                  helperText: place?['code'] == null ? null : 'Changing it breaks printed labels and the Godot link.',
                ),
              ),
              if (!isRoom)
                DropdownButton<String>(
                  value: tier,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'fast', child: Text('fast (everyday storage)')),
                    DropdownMenuItem(value: 'long', child: Text('long (-2 floor, long-term)')),
                  ],
                  onChanged: (v) => set(() => tier = v!),
                ),
              DropdownButton<int?>(
                value: parent,
                isExpanded: true,
                hint: const Text('Inside (none: top level)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Top level')),
                  for (final (p, depth) in placeTree(refs.places))
                    if (p['id'] != place?['id'])
                      DropdownMenuItem(value: p['id'] as int, child: Text('${'  ' * depth}${refs.placeName(p['id'] as int)}')),
                ],
                onChanged: (v) => set(() => parent = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final c = code.text.trim().toUpperCase();
  if (name.text.trim().isEmpty) {
    say(context, 'Give the place a name.');
    return null;
  }
  if (c.isNotEmpty && !validCode(c)) {
    say(context, 'A code is capitals, digits and dashes, like B2-R1-S2.');
    return null;
  }
  try {
    final saved = await savePlace({
      'name': name.text.trim(),
      'code': c.isEmpty ? null : c,
      'parent_id': parent,
      if (!isRoom) ...{'kind': 'storage', 'tier': tier},
    }, place?['id'] as int?);
    refs.places
      ..removeWhere((p) => p['id'] == saved['id'])
      ..add(saved);
    return saved;
  } catch (e) {
    if (context.mounted) say(context, 'Could not save: $e');
    return null;
  }
}

class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  late final refs = widget.refs;
  late Future<List<Rec>> data = stock();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Places')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        if (await editPlace(context, refs) != null) setState(() => data = stock());
      },
      icon: const Icon(Icons.add),
      label: const Text('Add place'),
    ),
    body: FutureBuilder(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        final rows = snap.data;
        if (rows == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: [
            for (final (p, depth) in placeTree(refs.places))
              ListTile(
                contentPadding: EdgeInsets.only(left: 16.0 + 20 * depth, right: 16),
                title: Text(refs.placeName(p['id'] as int)),
                subtitle: Text(
                  [
                    p['tier'] ?? p['kind'],
                    '${rows.where((s) => s['place_id'] == p['id'] && s['qty'] != 0).length} items',
                    _day(p['counted_at']),
                  ].join(' · '),
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlacePage(refs: refs, place: p),
                    ),
                  );
                  setState(() => data = stock());
                },
              ),
          ],
        );
      },
    ),
  );
}

/// One place: what should be here, the stocktake, and movements from here.
class PlacePage extends StatefulWidget {
  const PlacePage({super.key, required this.refs, required this.place});
  final Refs refs;
  final Rec place;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  late final refs = widget.refs;
  late Rec place = widget.place;
  late Future<(List<Rec>, List<Rec>)> data = _load();
  bool counting = false;
  final counts = <int, TextEditingController>{};
  final seen = <int>{};

  int get id => place['id'] as int;

  Future<(List<Rec>, List<Rec>)> _load() async => (await stock(), await assetPlaces());

  void _reload() => setState(() {
    data = _load();
    counting = false;
  });

  /// Items here: total, and untagged = total minus the tagged ones that are here.
  (Map<int, num>, Map<int, num>, List<Rec>) _here(List<Rec> stockRows, List<Rec> where) {
    final total = {
      for (final s in stockRows)
        if (s['place_id'] == id && s['qty'] != 0) s['item_id'] as int: s['qty'] as num,
    };
    final hereIds = {
      for (final w in where)
        if (w['place_id'] == id) w['asset_id'],
    };
    final tagged = [
      for (final a in refs.assets)
        if (hereIds.contains(a['id'])) a,
    ];
    final untagged = {for (final e in total.entries) e.key: e.value - tagged.where((a) => a['item_id'] == e.key).length};
    return (total, untagged, tagged);
  }

  void _startCount(Map<int, num> untagged) => setState(() {
    counting = true;
    seen.clear();
    counts
      ..clear()
      ..addAll({for (final e in untagged.entries) e.key: TextEditingController(text: '${e.value}')});
  });

  Future<void> _saveCount(Map<int, num> untagged, List<Rec> tagged) async {
    final counted = <int, num>{};
    for (final e in counts.entries) {
      final n = num.tryParse(e.value.text.trim());
      if (n == null || n < 0) return say(context, 'Type a count (0 or more) for ${refs.itemNames[e.key]}.');
      counted[e.key] = n;
    }
    try {
      await addMovements(countAdjustments(untagged, counted, id, byStaff: refs.me));
      final now = DateTime.now().toUtc().toIso8601String();
      final found = [
        for (final a in tagged)
          if (seen.contains(a['id'])) a['id'] as int,
      ];
      final missing = [
        for (final a in tagged)
          if (!seen.contains(a['id'])) a['id'] as int,
      ];
      if (found.isNotEmpty) await updateAssets(found, {'seen_at': now, 'condition': 'ok'});
      if (missing.isNotEmpty) await updateAssets(missing, {'condition': 'missing'});
      for (final a in tagged) {
        a['condition'] = seen.contains(a['id']) ? 'ok' : 'missing';
      }
      await markCounted(id);
      place = {...place, 'counted_at': now};
      refs.places
        ..removeWhere((p) => p['id'] == id)
        ..add(place);
      if (mounted) say(context, 'Counted. ${missing.isEmpty ? '' : '${missing.length} tagged not found, marked missing.'}');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not save the count: $e');
    }
  }

  Future<void> _condition(Rec a) async {
    final c = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${a['tag']} is…'),
        children: [
          for (final c in const ['ok', 'broken', 'missing']) SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c)),
        ],
      ),
    );
    if (c == null) return;
    try {
      await updateAssets([a['id'] as int], {'condition': c});
      setState(() => a['condition'] = c);
    } catch (e) {
      if (mounted) say(context, 'Could not save: $e');
    }
  }

  Future<void> _tag() async {
    int? itemId;
    final tag = TextEditingController(), serial = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Tag an item here'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int?>(
                value: itemId,
                isExpanded: true,
                hint: const Text('Item'),
                items: [for (final i in refs.items) DropdownMenuItem(value: i['id'] as int, child: Text(i['name'] as String))],
                onChanged: (v) => set(() => itemId = v),
              ),
              TextField(
                controller: tag,
                decoration: const InputDecoration(labelText: 'Tag (empty: next TL number)'),
              ),
              TextField(
                controller: serial,
                decoration: const InputDecoration(labelText: 'Serial number (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tag it')),
          ],
        ),
      ),
    );
    if (ok != true || itemId == null) return;
    try {
      // a new tag for something already counted here: the tag is received, and the untagged count drops by one
      final a = await addAsset(itemId!, tag.text.toUpperCase(), serial.text);
      await addMovements([
        movementRow(kind: 'receive', itemId: itemId!, qty: 1, to: id, assetId: a['id'] as int, byStaff: refs.me, note: 'tagged'),
        movementRow(kind: 'adjust', itemId: itemId!, qty: -1, to: id, byStaff: refs.me, note: 'tagged'),
      ]);
      refs.assets.add(a);
      if (mounted) say(context, 'Tagged ${a['tag']}. Print its label with scripts/labels.py --assets.');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not tag: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = place['parent_id'] == null ? null : refs.placeName(place['parent_id'] as int);
    return Scaffold(
      appBar: AppBar(
        // opened from a QR label: nothing to go back to, so offer the office instead
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                tooltip: 'Office',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const BookingsPage())),
              ),
        title: Text(refs.placeName(id)),
        actions: [
          IconButton(
            tooltip: 'Edit place',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await editPlace(context, refs, place: place);
              if (saved != null) setState(() => place = saved);
            },
          ),
          IconButton(
            tooltip: 'Add a place inside',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => editPlace(context, refs, parentId: id),
          ),
          IconButton(tooltip: 'Tag an item', icon: const Icon(Icons.qr_code_2), onPressed: _tag),
        ],
      ),
      floatingActionButton: counting
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                if (await recordMovement(context, refs, placeId: id)) _reload();
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Record movement'),
            ),
      body: FutureBuilder(
        future: data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
          final loaded = snap.data;
          if (loaded == null) return const Center(child: CircularProgressIndicator());
          final (total, untagged, tagged) = _here(loaded.$1, loaded.$2);
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              ListTile(
                title: Text([if (parent != null) 'in $parent', place['tier'] ?? place['kind'], _day(place['counted_at'])].join(' · ')),
                trailing: counting
                    ? Wrap(
                        spacing: 8,
                        children: [
                          TextButton(onPressed: () => setState(() => counting = false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => _saveCount(untagged, tagged), child: const Text('Save count')),
                        ],
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _startCount(untagged),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Count'),
                      ),
              ),
              if (counting)
                const ListTile(
                  dense: true,
                  title: Text('Type what is really here. Tick each tagged item you see; unticked ones are marked missing.'),
                ),
              if (total.isEmpty && !counting) const ListTile(title: Text('Nothing recorded here.')),
              for (final e in (counting ? untagged : total).entries)
                ListTile(
                  title: Text(refs.itemNames[e.key] ?? 'item ${e.key}'),
                  subtitle: counting || untagged[e.key] == e.value ? null : Text('${untagged[e.key]} untagged'),
                  trailing: counting
                      ? SizedBox(
                          width: 80,
                          child: TextField(
                            controller: counts[e.key],
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        )
                      : Text('${e.value}', style: Theme.of(context).textTheme.titleMedium),
                ),
              if (tagged.isNotEmpty) const ListTile(dense: true, title: Text('Tagged')),
              for (final a in tagged)
                counting
                    ? CheckboxListTile(
                        value: seen.contains(a['id']),
                        onChanged: (v) => setState(() => v! ? seen.add(a['id'] as int) : seen.remove(a['id'])),
                        title: Text('${a['tag']} · ${refs.itemNames[a['item_id']]}'),
                        subtitle: a['serial'] == null ? null : Text('${a['serial']}'),
                      )
                    : ListTile(
                        title: Text('${a['tag']} · ${refs.itemNames[a['item_id']]}'),
                        subtitle: Text([if (a['serial'] != null) a['serial'], a['condition']].join(' · ')),
                        trailing: a['condition'] == 'ok' ? null : const Icon(Icons.error_outline, color: Colors.orange),
                        onTap: () => _condition(a),
                      ),
            ],
          );
        },
      ),
    );
  }
}

/// The screen a QR label opens (office/?place=CODE), once refs are loaded.
class PlaceLinkPage extends StatelessWidget {
  const PlaceLinkPage({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: loadRefs(),
    builder: (context, snap) {
      if (snap.hasError) return Scaffold(body: Center(child: Text('Could not load: ${snap.error}')));
      final refs = snap.data;
      if (refs == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final p = refs.placeByCode(code.toUpperCase());
      return p == null ? const BookingsPage() : PlacePage(refs: refs, place: p);
    },
  );
}
```

- [ ] **Step 6 (pi): replace `apps/office/lib/main.dart`**

```dart
// Lab office: staff sign in with an email link, then log, approve and equip bookings.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookings.dart';
import 'data.dart';
import 'places.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY'); // public by design: anon has no grants, RLS decides

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // browser tests read the semantics tree; build with --dart-define=E2E=true (off in production)
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey, httpClient: TimeoutClient());
  } catch (e) {
    // a bad key or no network at boot must not leave a blank white page (lesson from UNIDCOM RIMS)
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Could not start the office: $e')))));
    return;
  }
  runApp(const OfficeApp());
}

class OfficeApp extends StatelessWidget {
  const OfficeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lab office',
        theme: ThemeData(colorSchemeSeed: const Color(0xFFB3261E)),
        // 24-hour clock everywhere, time pickers included, whatever the phone's locale says
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
        home: StreamBuilder<AuthState>(
          stream: db.auth.onAuthStateChange,
          // a QR label opens office/?place=CODE. ponytail: signing in drops the query, so staff stay signed in on their phones
          builder: (context, _) => db.auth.currentSession == null
              ? const LoginPage()
              : Uri.base.queryParameters['place'] == null
                  ? const BookingsPage()
                  : PlaceLinkPage(code: Uri.base.queryParameters['place']!),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  String? message;

  Future<void> _send() async {
    setState(() => message = 'Sending…');
    try {
      await db.auth.signInWithOtp(
        email: email.text.trim().toLowerCase(),
        shouldCreateUser: false, // staff accounts are created by an admin; nobody signs up here
        emailRedirectTo: Uri.base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'[?#]+$'), ''),
      );
      setState(() => message = 'Check your inbox: the link signs you in on this browser.');
    } on AuthException catch (e) {
      setState(() => message = e.message.contains('not allowed') || e.statusCode == '422'
          ? 'This email is not a lab staff account.'
          : e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Lab office', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Staff email'),
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _send, child: const Text('Send sign-in link')),
              if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!)),
            ]),
          ),
        ),
      );
}
```

- [ ] **Step 7 (controller):** `cd apps/office && flutter analyze && flutter test` → no issues, all pass. Then `flutter build web --release --base-href /openlabtwin/office/` builds.

- [ ] **Commit**

```bash
git add apps/office
git commit -m "Office: Places, place screen with stocktake, tagged items, Needs attention, ?place= QR link

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 5: QR labels

- [ ] **Step 1 (pi): create `tests/test_labels.py`**

```python
"""Run: uv run python tests/test_labels.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import labels  # noqa: E402

places = [{"id": 1, "code": "R15", "name": "Room 15", "parent_id": None},
          {"id": 2, "code": "R15-L", "name": "Left", "parent_id": 1},
          {"id": 3, "code": "R15-L-S1", "name": "Shelf 1", "parent_id": 2},
          {"id": 4, "code": "B2", "name": "-2 floor", "parent_id": None},
          {"id": 5, "code": None, "name": "No code yet", "parent_id": 4}]
assert [p["code"] for p in labels.subtree(places, "R15-L")] == ["R15-L", "R15-L-S1"]
assert [p["code"] for p in labels.subtree(places, None)] == ["R15", "R15-L", "R15-L-S1", "B2"], "parents first, uncoded left out"
assert labels.place_url("R15-L-S1") == "https://berlogabob.github.io/openlabtwin/office/?place=R15-L-S1"
page = labels.label_html([("R15-L-S1", "Shelf <1>", labels.place_url("R15-L-S1"))])
assert page.count("<svg") == 1 and "R15-L-S1" in page and "Shelf &lt;1&gt;" in page and "@page" in page
print("ok")
```

- [ ] **Step 2 (pi): create `scripts/labels.py`**

```python
"""Printable QR labels for places and assets: an A4 HTML page, 3 × 8 labels, each QR opening the office at that place.

Usage: uv run python scripts/labels.py [--root CODE] [--assets] [--out FILE]
  --root CODE   only that place and everything under it (default: every place with a code)
  --assets      asset tags instead (the QR opens the place the asset lives in)
  --out FILE    default ~/Downloads/labels.html; open it in a browser and print at 100 %.
Staff-only data (where each asset is), so the page is written locally, never to the repo or the site.
"""
import html
import sys
from pathlib import Path

import segno

OFFICE = "https://berlogabob.github.io/openlabtwin/office/"


def place_url(code):
    return f"{OFFICE}?place={code}"


def subtree(places, root):
    """Places under (and including) the one with code `root`, parents before children."""
    kids = {}
    for p in places:
        kids.setdefault(p["parent_id"], []).append(p)
    start = [p for p in places if p["code"] == root] if root else [p for p in places if p["parent_id"] is None]
    out, stack = [], list(reversed(start))
    while stack:
        p = stack.pop()
        out.append(p)
        stack += reversed(sorted(kids.get(p["id"], []), key=lambda k: k["code"] or ""))
    return [p for p in out if p["code"]]


def label_html(labels):
    """labels: (big text, small text, url) triples -> one printable page."""
    cells = "".join(
        f'<div class="l">{segno.make(url, error="m").svg_inline(scale=3, border=0)}'
        f'<div><b>{html.escape(big)}</b><span>{html.escape(small)}</span></div></div>'
        for big, small, url in labels)
    return ("<!doctype html><meta charset=utf-8><title>Labels</title><style>"
            "@page{size:A4;margin:10mm}body{margin:0;font:11px system-ui,sans-serif}"
            ".g{display:grid;grid-template-columns:repeat(3,1fr);grid-auto-rows:34mm;gap:0}"
            ".l{display:flex;gap:3mm;align-items:center;padding:3mm;border:1px dashed #bbb;break-inside:avoid;overflow:hidden}"
            ".l svg{width:26mm;height:26mm;flex:none}b{display:block;font-size:16px;letter-spacing:.5px}span{color:#444}"
            f'</style><div class="g">{cells}</div>')


def main():
    from db import connect, select
    args = sys.argv[1:]
    root = args[args.index("--root") + 1] if "--root" in args else None
    out = Path(args[args.index("--out") + 1] if "--out" in args else Path.home() / "Downloads/labels.html")
    db = connect()
    places = select(db, "places", {"select": "id,code,name,parent_id", "order": "id"})
    chosen = subtree(places, root)
    if "--assets" in args:
        where = {w["asset_id"]: w["place_id"] for w in select(db, "asset_place", {"select": "asset_id,place_id", "order": "asset_id"})}
        codes = {p["id"]: p["code"] for p in chosen}
        rows = select(db, "assets", {"select": "id,tag,items(name)", "order": "tag"})
        labels = [(a["tag"], a["items"]["name"], place_url(codes[where[a["id"]]])) for a in rows if where.get(a["id"]) in codes]
    else:
        labels = [(p["code"], p["name"], place_url(p["code"])) for p in chosen]
    out.write_text(label_html(labels), encoding="utf-8")
    print(f"{len(labels)} labels -> {out}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3 (controller):** `uv run python tests/test_labels.py` → `ok`.

- [ ] **Commit**

```bash
git add scripts/labels.py tests/test_labels.py
git commit -m "Printable QR labels for places and tagged items

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 6: Read-only mirror on the edge node

- [ ] **Step 1 (pi): create `tests/test_mirror.py`**

```python
"""Run: uv run python tests/test_mirror.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import mirror  # noqa: E402

assert mirror.column_type("id", [1, 2]) == "bigint"
assert mirror.column_type("qty", [1, 2.5]) == "numeric"
assert mirror.column_type("public", [True, False]) == "boolean"
assert mirror.column_type("counted_at", [None]) == "timestamptz" and mirror.column_type("at", ["2026-09-26T10:00:00+00:00"]) == "timestamptz"
assert mirror.column_type("place_ids", [[1, 2]]) == "jsonb" and mirror.column_type("note", [None, "x"]) == "text"
sql = mirror.table_sql("items", [{"id": 1, "name": "Cabo $j$ HDMI", "note": None}])
assert sql.startswith("drop table if exists items cascade;") and '"id" bigint, "name" text, "note" text' in sql
assert "$jj$" in sql, "the dollar quote never collides with the data"
assert mirror.table_sql("empty", []).endswith("create table empty ();")
print("ok")
```

- [ ] **Step 2 (pi): create `scripts/mirror.py`**

```python
"""Read-only copy of the database on the edge node: loads the newest nightly backup into the local Postgres `openlabtwin`.

Usage (on the node): uv run python scripts/mirror.py [backup_root]     (default ~/openlabtwin-backups)
Supabase stays the only place anything is written. Each run replaces every mirrored table, then checks row counts.
Query it with: psql openlabtwin
"""
import json
import subprocess
import sys
from pathlib import Path

from backup import TABLES

# The views staff use most, over the mirrored tables (same definitions as the migrations).
VIEWS = """
create view stock as
  select item_id, place_id, sum(qty) as qty from (
    select item_id, to_place as place_id, qty from movements where to_place is not null
    union all select item_id, from_place, -qty from movements where from_place is not null) m
  group by item_id, place_id;
create view on_loan as
  select item_id, person_id, sum(case kind when 'issue' then qty else -qty end) as qty from movements
  where kind in ('issue', 'return') and person_id is not null group by item_id, person_id
  having sum(case kind when 'issue' then qty else -qty end) <> 0;
create view asset_place as
  select distinct on (asset_id) asset_id,
         case when kind in ('issue', 'consume') or (kind = 'adjust' and qty < 0) then null else to_place end as place_id,
         case when kind = 'issue' then person_id end as person_id, at
  from movements where asset_id is not null order by asset_id, at desc, id desc;
"""


def column_type(name, values):
    """A Postgres type from a column's JSON values. ponytail: guessed from the data; timestamps by the *_at / at naming rule."""
    seen = [v for v in values if v is not None]
    if name == "at" or name.endswith("_at"):
        return "timestamptz"
    if not seen:
        return "text"
    if all(isinstance(v, bool) for v in seen):
        return "boolean"
    if all(isinstance(v, int) and not isinstance(v, bool) for v in seen):
        return "bigint"
    if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in seen):
        return "numeric"
    if any(isinstance(v, (dict, list)) for v in seen):
        return "jsonb"
    return "text"


def dollar(text):
    tag = "$j$"
    while tag in text:
        tag = tag[:-1] + "j$"
    return f"{tag}{text}{tag}"


def table_sql(name, rows):
    """Drop and recreate one table from its backup rows."""
    cols = list(dict.fromkeys(k for r in rows for k in r))
    if not cols:
        return f"drop table if exists {name} cascade; create table {name} ();"
    spec = ", ".join(f'"{c}" {column_type(c, [r.get(c) for r in rows])}' for c in cols)
    return (f"drop table if exists {name} cascade;"
            f"create table {name} as select * from jsonb_to_recordset({dollar(json.dumps(rows, ensure_ascii=False))}::jsonb) as x({spec});")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "openlabtwin-backups")
    day = max(p for p in root.iterdir() if p.is_dir() and len(p.name) == 10)
    data = {t: json.loads((day / f"{t}.json").read_text(encoding="utf-8")) for t in TABLES if (day / f"{t}.json").exists()}
    sql = "begin;" + "".join(table_sql(t, rows) for t, rows in data.items()) + VIEWS + "commit;"
    subprocess.run(["psql", "-q", "-v", "ON_ERROR_STOP=1", "openlabtwin"], input=sql, text=True, check=True)
    counts = "select " + ", ".join(f"(select count(*) from {t})" for t in data) + ";"
    got = subprocess.run(["psql", "-tA", "-F", " ", "openlabtwin", "-c", counts], capture_output=True, text=True, check=True).stdout.split()
    bad = [f"{t}: {g} != {len(r)}" for (t, r), g in zip(data.items(), got) if int(g) != len(r)]
    if bad:
        sys.exit("mirror count mismatch: " + "; ".join(bad))
    print(f"mirrored {day.name}: " + ", ".join(f"{t} {len(r)}" for t, r in data.items()))


if __name__ == "__main__":
    main()
```

- [ ] **Step 3 (pi): replace `scripts/edge-setup.sh`**

```bash
#!/usr/bin/env bash
# One-command setup of the lab edge node (MX Linux / Debian): publishing, backups, idea hub AI, TV showcase, database mirror. Safe to run again.
# See docs/edge-node.md.
#   curl -fsSL https://raw.githubusercontent.com/berlogabob/openlabtwin/main/scripts/edge-setup.sh | bash
#   (or, from a clone:  scripts/edge-setup.sh [--dry-run])
set -euo pipefail
DRY=$([ "${1:-}" = "--dry-run" ] && echo 1 || echo 0)
REPO=git@github.com:berlogabob/openlabtwin.git
DIR=$HOME/openlabtwin
KEY=$HOME/.ssh/openlabtwin
run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }
step() { echo; echo "== $*"; }

step "1/10 packages (git, curl, openssh-server) and SSH at boot"
run sudo apt-get update -qq
run sudo apt-get install -y -qq git curl openssh-server cron
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then run sudo systemctl enable --now ssh cron
else run sudo update-rc.d ssh enable; run sudo update-rc.d cron enable; run sudo service ssh start; run sudo service cron start; fi

step "2/10 uv"
command -v uv >/dev/null || [ -x "$HOME/.local/bin/uv" ] || run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
export PATH="$HOME/.local/bin:$PATH"

step "3/10 deploy key (write access to this repo only)"
if [ ! -f "$KEY" ]; then run ssh-keygen -t ed25519 -f "$KEY" -N "" -C "lab edge node"; fi
# the IADE network blocks outgoing port 22: talk to GitHub over SSH on port 443 (ssh.github.com)
grep -q "IdentityFile $KEY" "$HOME/.ssh/config" 2>/dev/null || run sh -c "printf 'Host github.com\n  Hostname ssh.github.com\n  Port 443\n  User git\n  IdentityFile $KEY\n  StrictHostKeyChecking accept-new\n' >> '$HOME/.ssh/config'"
if [ "$DRY" = 0 ] && ! ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "Add this key at https://github.com/berlogabob/openlabtwin/settings/keys  (tick 'Allow write access'):"
  cat "$KEY.pub"; read -rp "Press Enter once it is added… " _ </dev/tty
fi

step "4/10 clone"
if [ -d "$DIR/.git" ]; then run git -C "$DIR" pull -q --rebase; else run git clone -q "$REPO" "$DIR"; fi
run git -C "$DIR" config user.name "lab edge node"
run git -C "$DIR" config user.email "lab-edge-node@users.noreply.github.com"

step "5/10 secrets (.env, mode 600)"
if [ ! -f "$DIR/.env" ]; then
  if [ "$DRY" = 1 ]; then echo "  would ask for the service role key and write $DIR/.env"
  else read -rsp "Supabase service role key (input hidden): " SK </dev/tty; echo
    umask 077; printf 'SUPABASE_URL=https://huqecytswaswkswofrqd.supabase.co\nSUPABASE_SERVICE_KEY=%s\n' "$SK" > "$DIR/.env"; fi
fi

step "6/10 local AI for the idea hub (Ollama; ornith only with >= 16 GB RAM)"
command -v ollama >/dev/null || run sh -c 'curl -fsSL https://ollama.com/install.sh | sh'
if ! command -v systemctl >/dev/null || [ ! -d /run/systemd/system ]; then   # sysVinit: start Ollama from cron at boot
  OLLAMA_BOOT="@reboot ollama serve >> \$HOME/ollama.log 2>&1"
  pgrep -x ollama >/dev/null || run sh -c 'nohup ollama serve >> "$HOME/ollama.log" 2>&1 &'
fi
# wait until Ollama answers (a slow PC can take a while to start it)
if [ "$DRY" = 0 ]; then for _ in $(seq 1 30); do ollama list >/dev/null 2>&1 && break; sleep 2; done; fi
run ollama pull nomic-embed-text
RAM_GB=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$RAM_GB" -ge 16 ]; then run ollama pull ornith-1.5:9b
else echo "  only ${RAM_GB} GB RAM: ornith (about 8 GB) won't fit comfortably. In $DIR/.env set IDEAS_MODEL to a small model"
     echo "  (e.g. IDEAS_MODEL=qwen2.5:3b after: ollama pull qwen2.5:3b) or OLLAMA_URL to a machine that runs ornith."; fi

step "7/10 first run (sync deps, scrape, export, push if changed, backup)"
run sh -c "cd '$DIR' && uv sync -q && scripts/publish.sh --scrape && set -a && . ./.env && set +a && uv run python scripts/backup.py && { uv run python scripts/ideas_ai.py || echo '  idea AI not reachable now; cron retries every 15 min'; }"

step "8/10 cron (publish every 10 min, scrape every 6 h, idea AI every 15 min, TV playlist every minute, backup and mirror nightly)"
CRON="*/10 * * * *  cd $DIR && scripts/publish.sh          >> \$HOME/publish.log 2>&1
15 */6 * * *  cd $DIR && scripts/publish.sh --scrape >> \$HOME/publish.log 2>&1
*/15 * * * *  cd $DIR && set -a && . ./.env && set +a && $HOME/.local/bin/uv run python scripts/ideas_ai.py >> \$HOME/ideas_ai.log 2>&1
* * * * *  cd $DIR && set -a && . ./.env && set +a && $HOME/.local/bin/uv run python scripts/tv.py > /dev/null 2>> \$HOME/tv.log
30 3 * * *    cd $DIR && set -a && . ./.env && set +a && $HOME/.local/bin/uv run python scripts/backup.py >> \$HOME/backup.log 2>&1
45 3 * * *    cd $DIR && $HOME/.local/bin/uv run python scripts/mirror.py >> \$HOME/mirror.log 2>&1${OLLAMA_BOOT:+
$OLLAMA_BOOT}"
if [ "$DRY" = 1 ]; then echo "  would install (replacing older openlabtwin lines):"; echo "$CRON" | sed 's/^/    /'
else { crontab -l 2>/dev/null | grep -v openlabtwin || true; echo "PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"; echo "$CRON"; } \
  | awk '!seen[$0]++' | crontab -; crontab -l; fi

step "9/10 TV showcase (nginx serves http://<ip>/tv/, Samba shares ~/tv-media as smb://<ip>/tv)"
run sudo apt-get install -y -qq nginx-light samba ffmpeg
run mkdir -p "$HOME/tv-media" "$HOME/tv-out/qr"
run chmod o+x "$HOME"   # nginx (www-data) may pass through home, and reads only what the site file names
run sh -c "sed 's#/home/TechLAB#$HOME#g' '$DIR/scripts/tv-nginx.conf' | sudo tee /etc/nginx/sites-available/tv >/dev/null"
run sudo ln -sf /etc/nginx/sites-available/tv /etc/nginx/sites-enabled/tv
run sudo rm -f /etc/nginx/sites-enabled/default
run sudo nginx -t
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then run sudo systemctl enable --now nginx smbd; run sudo systemctl reload nginx
else run sudo service nginx reload; run sudo service smbd start; fi
if ! grep -q '^\[tv\]' /etc/samba/smb.conf 2>/dev/null; then
  run sh -c "printf '\n[tv]\n   path = $HOME/tv-media\n   valid users = $USER\n   read only = no\n   create mask = 0644\n   directory mask = 0755\n' | sudo tee -a /etc/samba/smb.conf >/dev/null"
  run sudo service smbd restart
fi
if ! grep -q 'veto files = /._\*/.DS_Store/' /etc/samba/smb.conf 2>/dev/null; then  # no Mac litter (._name, .DS_Store) in the share
  run sudo sed -i '/^\[tv\]/a\   veto files = /._*/.DS_Store/\n   delete veto files = yes' /etc/samba/smb.conf
  run sudo service smbd restart
fi
if [ "$DRY" = 0 ] && ! sudo pdbedit -L 2>/dev/null | grep -q "^$USER:"; then
  echo "  Samba password for $USER (used to connect to smb://<ip>/tv):"; sudo smbpasswd -a "$USER" </dev/tty
fi
if command -v ufw >/dev/null; then for net in 192.168.1.0/24 10.208.16.0/23; do
  run sudo ufw allow from "$net" to any port 80 proto tcp; run sudo ufw allow from "$net" to any port 445 proto tcp; done; fi

step "10/10 read-only database mirror (local Postgres, localhost only, loaded nightly from the backup)"
run sudo apt-get install -y -qq postgresql
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then run sudo systemctl enable --now postgresql
else run sudo update-rc.d postgresql enable; run sudo service postgresql start; fi
if [ "$DRY" = 0 ] && ! sudo -u postgres psql -tAc "select 1 from pg_roles where rolname = '$USER'" | grep -q 1; then
  run sudo -u postgres createuser --createdb "$USER"; fi
if [ "$DRY" = 0 ] && ! psql -lqt 2>/dev/null | cut -d'|' -f1 | grep -qw openlabtwin; then run createdb openlabtwin; fi
run sh -c "cd '$DIR' && uv run python scripts/mirror.py"

step "done: tail -f ~/publish.log   ·   ip: $(hostname -I 2>/dev/null | cut -d' ' -f1)"
```

- [ ] **Step 4 (controller):** `uv run python tests/test_mirror.py` → `ok`. `bash -n scripts/edge-setup.sh`, then `scripts/edge-setup.sh --dry-run | tail -12` shows step 10 and the 03:45 cron line.

- [ ] **Commit**

```bash
git add scripts/mirror.py tests/test_mirror.py scripts/edge-setup.sh
git commit -m "Edge node: read-only Postgres mirror loaded nightly from the backup

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TArcJAcFxarRo4kv9wMDtk"
```

---

### Task 7: Docs (controller)

Update in the commit that goes with them, per AGENTS.md:
- `ARCHITECTURE.md`: data model (codes, assets, asset_place, storage_issues, waivers, merge_items), the Godot contract, the mirror, a status row, "Deferred" (RFID still deferred).
- `STAFF-GUIDE.md`: Places, the place screen, stocktake, tagging, labels, Needs attention, merging.
- `OPERATIONS.md`: the import, labels, the mirror, and the new tests in the Tests table.
- `edge-node.md`: Postgres, the mirror and its cron.
- `ROADMAP.md`: the mirror is done, with the full local database still open; the first stocktakes (B2 racks, cupboard rooms); student loan records to settle; Godot reading places and stock.

---

### Task 8: Live (controller, with the user)

1. Import: review the dry run with the user, including the 13 "Not imported" rows. Then `--apply`. Check in the office: Places shows the tree, and Needs attention lists every stocked place as never counted.
2. Browser e2e (Playwright, `E2E=true` build, admin magic link):
   - open `office/?place=R15-L-S3` and count it: one adjust, the counted date set, its issue gone;
   - merge `Cabo HDMI` into `Cabos HDMI`.
3. `uv run python scripts/labels.py --root R15-L-S3`: print it, scan it with a phone, and the office opens the shelf.
4. Node: `git pull`, run edge-setup step 10 (or the whole script), `uv run python scripts/mirror.py`, then `psql openlabtwin -c 'select count(*) from stock'`.
5. Push. `sync.yml` deploys the office.
