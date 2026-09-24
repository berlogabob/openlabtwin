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

from db import connect, select
from ics import render_ics
from timetable_parse import TZ, monday_of

ROOT = Path(__file__).resolve().parent.parent
WINDOW_DAYS = 180  # how far ahead repeating activities are expanded
ICS_STAMP = "20260921T000000Z"  # ponytail: fixed DTSTAMP keeps lab.ics unchanged unless events change; UIDs + times carry updates
KEYS = frozenset({"date", "start", "end", "course", "groups", "teachers", "type", "rooms", "programmes", "degrees",
                  "layer", "note"})
LESSON_COLS = "date,start_time,end_time,course,groups,teachers,type,rooms,programmes,degrees"
ACTIVITY_COLS = ("id,title,layer,kind,place_ids,location_text,starts_at,ends_at,rrule,exdates,status,"
                 "requester_display,owner_staff_id,organization_id,public_note")


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


def activity_records(a, place_names, org_names, first, last, staff_names=None):
    rooms = [place_names[p] for p in a["place_ids"] if p in place_names]
    if not rooms and a.get("location_text"):
        rooms = [a["location_text"]]
    org = org_names.get(a.get("organization_id"))
    # the requester and the staff member in charge, so "Professor / staff" finds a technician's bookings
    people = list(dict.fromkeys(x for x in [a.get("requester_display"), (staff_names or {}).get(a.get("owner_staff_id"))] if x))
    return [{"date": s.date().isoformat(), "start": s.strftime("%H:%M"), "end": e.strftime("%H:%M"),
             "course": a["title"], "groups": [org] if org else [],
             "teachers": people,
             "type": a["kind"].capitalize(), "rooms": rooms, "programmes": [], "degrees": [],
             "layer": a["layer"], "note": a.get("public_note") or ""}
            for s, e in occurrences(a, first, last)]


def assert_whitelist(records):
    for r in records:
        stray = set(r) - KEYS
        assert not stray, f"record {r.get('course')!r} {r.get('date')} has forbidden keys: {sorted(stray)}"


def build(lessons, activities, places, organizations, today, staff=()):
    first = monday_of(today)
    last = first + timedelta(days=WINDOW_DAYS)
    place_names = {p["id"]: p["iade_name"] or p["name"] for p in places if p["public"]}
    org_names = {o["id"]: o["name"] for o in organizations}
    staff_names = {p["id"]: p["name"] for p in staff}
    out = [lesson_record(r) for r in lessons if r["date"] >= first.isoformat()]
    for a in activities:
        if a["status"] == "approved":  # also filtered in the query; checked again so a query change can't leak
            out += activity_records(a, place_names, org_names, first, last, staff_names)
    assert_whitelist(out)
    return sorted(out, key=lambda r: (r["date"], r["start"], r["course"]))


def render(records):
    """One record per line, like the current all.json, so git diffs stay readable."""
    return "[\n" + ",\n".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) for r in records) + "\n]\n"


def lab_items(records, lab_rooms):
    """One entry per lab room a record uses, in the shape render_ics() expects."""
    return [r | {"room": room, "source_url": ""} for r in records for room in r["rooms"] if room in lab_rooms]


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "apps/site/web"
    today = datetime.now(TZ).date()
    monday = monday_of(today).isoformat()
    db = connect()
    lessons = select(db, "lessons", {"select": LESSON_COLS, "date": f"gte.{monday}", "order": "id"})
    activities = select(db, "activities", {"select": ACTIVITY_COLS, "status": "eq.approved", "order": "id"})
    places = select(db, "places", {"select": "id,name,iade_name,public", "order": "id"})
    organizations = select(db, "organizations", {"select": "id,name", "order": "id"})
    staff = select(db, "people", {"select": "id,name", "is_staff": "eq.true", "order": "id"})  # names only, never emails
    records = build(lessons, activities, places, organizations, today, staff)
    if not any(r["layer"] == "lesson" for r in records):
        sys.exit("No lessons to export; refusing to publish an empty schedule.")
    lab_rooms = {p["iade_name"] or p["name"] for p in places if p["public"]}
    (out_dir / "data").mkdir(parents=True, exist_ok=True)
    (out_dir / "calendar").mkdir(parents=True, exist_ok=True)
    (out_dir / "data/all.json").write_text(render(records), encoding="utf-8")
    (out_dir / "calendar/lab.ics").write_text(render_ics(lab_items(records, lab_rooms), ICS_STAMP), encoding="utf-8",
                                              newline="")
    print(f"Exported {len(records)} records "
          f"({sum(r['layer'] == 'lesson' for r in records)} lessons) to {out_dir / 'data/all.json'} and lab.ics")


if __name__ == "__main__":
    main()
