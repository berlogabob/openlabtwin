"""Read-only storage counts for thesis metrics.

Usage: uv run python scripts/storage_snapshot.py [--out FILE]
Reads aggregate source rows with the service key; the output contains counts only.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json

import db


TABLES = {
    "places": ("id,counted_at", "id"),
    "items": ("id,merged_into", "id"),
    "assets": ("id,condition", "id"),
    "movements": ("id,kind,note", "id"),
    "on_loan": ("item_id,person_id,qty", "item_id"),
    "storage_issues": ("code", "code"),
}


def summarize(places, items, assets, movements, on_loan, issues, now):
    """Summarize storage rows without exposing their identifying fields."""
    counted = sum(row["counted_at"] is not None for row in places)
    conditions = Counter(row["condition"] for row in assets)
    kinds = Counter(row["kind"] for row in movements)
    sources = Counter()
    for row in movements:
        note = (row.get("note") or "").strip()
        prefix = note.split(":", 1)[0].strip().lower() if note else "none"
        sources[prefix] += 1
    issue_counts = Counter(row["code"] for row in issues)
    at = now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "at": at,
        "places": {"total": len(places), "counted": counted, "never_counted": len(places) - counted},
        "items": {"total": sum(row["merged_into"] is None for row in items),
                  "merged": sum(row["merged_into"] is not None for row in items)},
        "assets": {"total": len(assets), "by_condition": dict(sorted(conditions.items()))},
        "movements": {"total": len(movements), "by_kind": dict(sorted(kinds.items())),
                      "by_source": dict(sorted(sources.items()))},
        "open_loans": {"rows": len(on_loan), "qty": sum(row["qty"] for row in on_loan)},
        "issues": dict(sorted(issue_counts.items())),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out")
    args = parser.parse_args()

    conn = db.connect()
    data = {}
    for table, (columns, order) in TABLES.items():
        params = {"select": columns, "order": order}
        data[table] = db.fetch_all(
            lambda start, end, table=table, params=params: db.request(
                conn, "GET", table, params, headers={"Range": f"{start}-{end}"}))
    result = summarize(*(data[name] for name in TABLES), datetime.now(timezone.utc))
    line = json.dumps(result, indent=2, sort_keys=True)
    if args.out:
        with open(args.out, "a", encoding="utf-8") as output:
            output.write(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    else:
        print(line)


if __name__ == "__main__":
    main()
