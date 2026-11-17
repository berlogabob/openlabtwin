"""Read-only storage counts for thesis metrics.

Usage: uv run python scripts/storage_snapshot.py [--out FILE]
Reads aggregate source rows with the service key; the output contains counts only.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from statistics import median

import db


TABLES = {
    "places": ("id,counted_at", "id"),
    "items": ("id,merged_into", "id"),
    "assets": ("id,condition", "id"),
    "movements": ("id,kind,note,asset_id,at", "id"),
    "on_loan": ("item_id,person_id,qty", "item_id"),
    "storage_issues": ("code", "code"),
}


def summarize(places, items, assets, movements, on_loan, issues, now):
    """Summarize storage rows without exposing their identifying fields."""
    counted = sum(row["counted_at"] is not None for row in places)
    conditions = Counter(row["condition"] for row in assets)
    kinds = Counter(row["kind"] for row in movements)
    sources = Counter()
    channels = Counter()
    for row in movements:
        note = (row.get("note") or "").strip()
        prefix = note.split(":", 1)[0].strip().lower() if note else "none"
        sources[prefix] += 1
        # Closed vocabulary so free note text never reaches the metrics: tylog:* = bridge, import:* = scripts, rest = office forms.
        channel = prefix if prefix in ("tylog", "import") else "office"
        channels[channel] += 1
    tagged = sorted(
        (row for row in movements if row.get("asset_id") is not None and row["kind"] in {"issue", "return"}),
        key=lambda row: (row["at"], row["id"]),
    )
    returns_by_asset = {}
    for row in tagged:
        if row["kind"] == "return":
            returns_by_asset.setdefault(row["asset_id"], []).append(row)
    used_returns = set()
    gaps = []
    open_tagged = 0
    for issue in (row for row in tagged if row["kind"] == "issue"):
        returned = next((row for row in returns_by_asset.get(issue["asset_id"], [])
                         if row["id"] not in used_returns and (row["at"], row["id"]) > (issue["at"], issue["id"])), None)
        if returned is None:
            open_tagged += 1
            continue
        used_returns.add(returned["id"])
        start = datetime.fromisoformat(issue["at"].replace("Z", "+00:00"))
        end = datetime.fromisoformat(returned["at"].replace("Z", "+00:00"))
        gaps.append((end - start).total_seconds() / 3600)
    issue_counts = Counter(row["code"] for row in issues)
    at = now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    return {
        "at": at,
        "places": {"total": len(places), "counted": counted, "never_counted": len(places) - counted},
        "items": {"total": sum(row["merged_into"] is None for row in items),
                  "merged": sum(row["merged_into"] is not None for row in items)},
        "assets": {"total": len(assets), "by_condition": dict(sorted(conditions.items()))},
        "movements": {"total": len(movements), "by_kind": dict(sorted(kinds.items())),
                      "by_source": dict(sorted(sources.items())), "by_channel": dict(sorted(channels.items()))},
        "loans": {"returned": len(gaps), "median_hours": round(median(gaps), 1) if gaps else None,
                  "open_tagged": open_tagged},
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
