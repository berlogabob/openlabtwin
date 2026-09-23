"""Scrape the IADE timetable into the lessons table.

Usage: SUPABASE_URL=... SUPABASE_SERVICE_KEY=... uv run python scripts/timetable.py
"""
import hashlib
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from db import chunks, connect, request, select
from timetable_parse import (BASE, TZ, all_lessons_unique, degree, find_pages, get, group_programmes, monday_of,
                             parse_page)


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
    db = connect()
    existing = [r["hash"] for r in select(db, "lessons", {"select": "hash", "date": f"gte.{monday}", "order": "id"})]
    upserts, deletes = plan_sync(existing, rows)
    for c in chunks(upserts):
        request(db, "POST", "lessons", {"on_conflict": "hash"}, c,
                {"Prefer": "resolution=merge-duplicates,return=minimal"})
    for c in chunks(deletes, 100):  # hashes go in the URL; 100 keeps it short
        request(db, "DELETE", "lessons", {"hash": "in.(" + ",".join(c) + ")"}, headers={"Prefer": "return=minimal"})
    print(f"Upserted: {len(upserts)}\nDeleted: {len(deletes)}")


if __name__ == "__main__":
    main()
