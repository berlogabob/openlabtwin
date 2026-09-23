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
