"""Usage statistics as CSV files, for the thesis: what was used most, by which course, and what ran out.

Usage: uv run python scripts/usage_export.py [out_dir]      (default ~/Downloads/openlabtwin-usage-YYYY-MM-DD)
Reads the views usage_by_item, usage_by_course and peak_on_loan (archive sheets plus live loans) with the service key.
No names of people: the views count loans, they don't list who. Open the files in any spreadsheet.
"""
import csv
import io
import sys
from datetime import date
from pathlib import Path

VIEWS = {
    "usage_by_item": ("month", "name", "source", "loans", "units", "people"),
    "usage_by_course": ("course", "name", "loans", "units"),
    "peak_on_loan": ("name", "peak", "owned"),
}


def to_csv(rows, cols):
    """rows (dicts) as CSV text with exactly these columns, in this order."""
    out = io.StringIO()
    w = csv.writer(out, lineterminator="\n")
    w.writerow(cols)
    for r in rows:
        w.writerow(["" if r.get(c) is None else r[c] for c in cols])
    return out.getvalue()


def main():
    from db import connect, select
    out = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Downloads" / f"openlabtwin-usage-{date.today().isoformat()}")
    out.mkdir(parents=True, exist_ok=True)
    db = connect()
    for view, cols in VIEWS.items():
        rows = select(db, view, {"select": ",".join(cols), "order": cols[0]})
        (out / f"{view}.csv").write_text(to_csv(rows, cols), encoding="utf-8")
        print(f"{view}: {len(rows)} rows")
    print(f"-> {out}")


if __name__ == "__main__":
    main()
