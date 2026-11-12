"""Staff-only equipment booking report as CSV.

Usage: uv run python scripts/booking_report.py [--from YYYY-MM-DD] [--to YYYY-MM-DD] [out.csv]
Default: first of this month through today, ~/Downloads/equipment-requests-FROM-TO.csv.
Reads bookings, requested lines, movements, people and items with the service key.
The report holds names and emails; write it locally and keep it staff-only.
"""
import argparse
import csv
import io
from datetime import date
from pathlib import Path

COLUMNS = ("id", "date", "title", "requester", "email", "status", "items",
           "issued", "returned", "outstanding", "state")


def _number(value):
    return str(int(value)) if value == int(value) else str(value)


def report_rows(activities, lines, movements, people, item_names, start, end):
    people_by_id = {p["id"]: p for p in people}
    lines_by_activity = {}
    for line in lines:
        lines_by_activity.setdefault(line["activity_id"], []).append(line)
    for group in lines_by_activity.values():
        group.sort(key=lambda line: line["item_id"])

    totals = {}
    for movement in movements:
        kind = movement["kind"]
        if kind in ("issue", "return"):
            totals.setdefault(movement["activity_id"], {"issue": 0, "return": 0})[kind] += movement["qty"]

    selected = [a for a in activities if a["kind"] == "equipment"
                and start <= a["starts_at"][:10] <= end]
    selected.sort(key=lambda a: (a["starts_at"], a["id"]))
    rows = []
    for activity in selected:
        aid = activity["id"]
        person = people_by_id.get(activity.get("requester_id"))
        issued = totals.get(aid, {}).get("issue", 0)
        returned = totals.get(aid, {}).get("return", 0)
        outstanding = max(0, issued - returned)
        rows.append({
            "id": aid,
            "date": activity["starts_at"][:10],
            "title": activity["title"],
            "requester": (person or {}).get("name") or activity.get("requester_display") or "",
            "email": (person or {}).get("email") or "",
            "status": activity["status"],
            "items": "; ".join(
                f"{item_names.get(line['item_id'], 'item ' + str(line['item_id']))} x{_number(line['qty'])}"
                for line in lines_by_activity.get(aid, [])
            ),
            "issued": issued,
            "returned": returned,
            "outstanding": outstanding,
            "state": "not issued" if issued == 0 else "returned" if outstanding == 0 else "outstanding",
        })
    return rows


def to_csv(rows):
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(COLUMNS)
    for row in rows:
        writer.writerow(["" if row.get(column) is None else row[column] for column in COLUMNS])
    return out.getvalue()


def main():
    today = date.today()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from", dest="start", default=today.replace(day=1).isoformat())
    parser.add_argument("--to", dest="end", default=today.isoformat())
    parser.add_argument("out", nargs="?")
    args = parser.parse_args()
    start, end = date.fromisoformat(args.start), date.fromisoformat(args.end)
    if start > end:
        parser.error("--from must be on or before --to")
    output = Path(args.out) if args.out else Path.home() / "Downloads" / f"equipment-requests-{start}-{end}.csv"

    from db import connect, select
    db = connect()
    activities = select(db, "activities", {"select": "id,starts_at,title,requester_id,requester_display,status,kind", "kind": "eq.equipment", "order": "starts_at,id"})
    lines = select(db, "activity_items", {"select": "activity_id,item_id,qty", "order": "activity_id,item_id"})
    movements = select(db, "movements", {"select": "activity_id,kind,qty", "activity_id": "not.is.null", "kind": "in.(issue,return)"})
    people = select(db, "people", {"select": "id,name,email"})
    items = select(db, "items", {"select": "id,name"})
    rows = report_rows(activities, lines, movements, people,
                       {item["id"]: item["name"] for item in items}, start.isoformat(), end.isoformat())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(to_csv(rows), encoding="utf-8")
    print(f"{len(rows)} rows -> {output}")


if __name__ == "__main__":
    main()
