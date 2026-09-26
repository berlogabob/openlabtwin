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


# An empty table's JSON has no columns, but the views need these. ponytail: copied from the migrations; keep in step.
EMPTY = {"movements": '"id" bigint, "item_id" bigint, "qty" numeric, "from_place" bigint, "to_place" bigint, "kind" text, '
                      '"person_id" bigint, "activity_id" bigint, "by_staff" bigint, "at" timestamptz, "asset_id" bigint, "note" text'}


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
        return f"drop table if exists {name} cascade; create table {name} ({EMPTY.get(name, '')});"
    spec = ", ".join(f'"{c}" {column_type(c, [r.get(c) for r in rows])}' for c in cols)
    return (f"drop table if exists {name} cascade;"
            f"create table {name} as select * from jsonb_to_recordset({dollar(json.dumps(rows, ensure_ascii=False))}::jsonb) as x({spec});")


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "openlabtwin-backups")
    day = max(p for p in root.iterdir() if p.is_dir() and len(p.name) == 10)
    data = {t: json.loads((day / f"{t}.json").read_text(encoding="utf-8")) for t in TABLES if (day / f"{t}.json").exists()}
    sql = "set client_min_messages = warning; begin;" + "".join(table_sql(t, rows) for t, rows in data.items()) + VIEWS + "commit;"
    subprocess.run(["psql", "-q", "-v", "ON_ERROR_STOP=1", "openlabtwin"], input=sql, text=True, check=True)
    counts = "select " + ", ".join(f"(select count(*) from {t})" for t in data) + ";"
    got = subprocess.run(["psql", "-tA", "-F", " ", "openlabtwin", "-c", counts], capture_output=True, text=True, check=True).stdout.split()
    bad = [f"{t}: {g} != {len(r)}" for (t, r), g in zip(data.items(), got) if int(g) != len(r)]
    if bad:
        sys.exit("mirror count mismatch: " + "; ".join(bad))
    print(f"mirrored {day.name}: " + ", ".join(f"{t} {len(r)}" for t, r in data.items()))


if __name__ == "__main__":
    main()
