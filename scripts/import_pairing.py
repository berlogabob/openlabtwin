"""Import consoles from the office's final pairing CSV.

Usage: uv run python scripts/import_pairing.py PAIRING.csv [--place CODE=LAB-VIT]
       [--item NAME="Consola PS4 Slim"] [--sql] [--apply]
Dry run is the default; --apply writes one transaction.
"""
import argparse
import csv
from io import StringIO
import re
import sys


CONSOLE = re.compile(r"(?<!\d)(\d{2})[-\s]?(\d{8})[-\s]?(\d{7})(?!\d)")


def console_key(serial):
    match = CONSOLE.search(str(serial or ""))
    return (match[2], match[3]) if match else None


def pretty_serial(serial):
    match = CONSOLE.search(str(serial or ""))
    return f"{match[1]}-{match[2]}-{match[3]}" if match else None


def read_rows(csv_text, bad=None):
    rows, seen = [], set()
    for row in csv.DictReader(StringIO(csv_text, newline="")):
        serial = str(row.get("console_serial") or "").strip()
        if not serial:
            continue
        key = console_key(serial)
        if key is None:
            if bad is not None:
                bad.append(serial)
            continue
        if key in seen:
            continue
        seen.add(key)
        rows.append({"serial": pretty_serial(serial), "key": key,
                     "box": str(row.get("box_serial") or "").strip(),
                     "status": str(row.get("status") or "").strip()})
    return rows


def plan(rows, existing):
    by_key = {console_key(asset.get("serial")): asset["tag"] for asset in existing
              if console_key(asset.get("serial"))}
    new, present = [], []
    for row in rows:
        tag = by_key.get(row["key"])
        (present if tag else new).append({**row, **({"tag": tag} if tag else {})})
    return new, present


def lit(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def box_note(row):
    note = f"box serial: {row['box']}"
    if row["status"] == "no_box":
        note += "; no box"
    elif row["status"] == "move":
        note += f"; moves into box {row['box']}"
    return note


def apply_sql(new, place, item):
    out = [f"do $$ begin if not exists (select 1 from items where name = {lit(item)}) then "
           f"raise exception 'Unknown item'; end if; if not exists (select 1 from places where code = {lit(place)}) then "
           f"raise exception 'Unknown place'; end if; end $$;"]
    for row in new:
        note = box_note(row)
        out.append(f"insert into assets (item_id, serial, condition, note) select id, {lit(row['serial'])}, 'ok', {lit(note)} "
                   f"from items where name = {lit(item)};")
        out.append(f"insert into movements (item_id, asset_id, qty, to_place, kind, note) "
                   f"select a.item_id, a.id, 1, p.id, 'receive', 'import: pairing CSV' from assets a, places p "
                   f"where a.serial = {lit(row['serial'])} and p.code = {lit(place)};")
    serials = ", ".join(lit(row["serial"]) for row in new) or "null"
    out.append(f"select tag, serial from assets where serial in ({serials}) order by tag;")
    return "\n".join(out)


def fetch_existing():
    import db
    conn = db.connect()
    return db.select(conn, "assets", {"select": "tag,serial", "order": "tag"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv")
    parser.add_argument("--place", default="LAB-VIT")
    parser.add_argument("--item", default="Consola PS4 Slim")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--sql", action="store_true")
    args = parser.parse_args()
    bad = []
    with open(args.csv, encoding="utf-8-sig", newline="") as f:
        rows = read_rows(f.read(), bad)
    existing = fetch_existing()
    new, present = plan(rows, existing)
    print(f"{len(rows) + len(bad)} consoles in CSV: {len(new)} new, {len(present)} already registered (tag), {len(bad)} unreadable")
    for serial in bad:
        print(f"Unreadable console serial: {serial}")
    for row in new:
        print(row["serial"])
    sql = apply_sql(new, args.place, args.item)
    if args.sql:
        print(sql)
    if args.apply:
        if bad:
            sys.exit("Refusing to apply: unreadable console serials exist.")
        import sqltest
        result, err = sqltest.query(sql)
        if err:
            sys.exit(f"Nothing written: {err}")
        print("New tags:")
        for row in result or []:
            print(f"{row['tag']}\t{row['serial']}")


if __name__ == "__main__":
    main()
