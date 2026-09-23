"""Run: uv run python tests/test_export.py"""
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import export  # noqa: E402

places = [{"id": 1, "name": "Tech Lab", "iade_name": "Lab. e Estudo de Jogos - Tech Lab (Oriente)", "public": True},
          {"id": 2, "name": "Long-term storage", "iade_name": None, "public": False}]
orgs = [{"id": 7, "name": "RobotClub"}]
lesson = {"date": "2026-09-21", "start_time": "09:00:00", "end_time": "11:00:00", "course": "Game Frameworks",
          "groups": ["G1"], "teachers": ["T"], "type": "P", "rooms": ["Sala 1"], "programmes": ["P"],
          "degrees": ["Bachelor"]}
club = {"id": 1, "title": "Club meeting", "layer": "booking", "kind": "club", "place_ids": [1, 2],
        "location_text": None, "starts_at": "2026-10-20T16:00:00+00:00", "ends_at": "2026-10-20T18:00:00+00:00",
        "rrule": "FREQ=WEEKLY;COUNT=3", "exdates": ["2026-10-27"], "status": "approved",
        "requester_display": "Prof. Cláudia", "organization_id": 7, "public_note": "Bring laptops"}
fair = {"id": 2, "title": "Open day", "layer": "event", "kind": "external", "place_ids": [],
        "location_text": "Aula Magna", "starts_at": "2026-09-25T09:00:00+00:00", "ends_at": "2026-09-25T12:00:00+00:00",
        "rrule": None, "exdates": [], "status": "approved", "requester_display": None, "organization_id": None,
        "public_note": None}
pending = club | {"id": 3, "title": "Secret", "status": "requested", "rrule": None}

out = export.build([lesson, lesson | {"date": "2026-09-20"}], [club, fair, pending], places, orgs, date(2026, 9, 23))

assert all(set(r) == export.KEYS for r in out), out
assert not any(r["course"] == "Secret" for r in out), "unapproved activity was exported"
assert [r["date"] for r in out if r["layer"] == "lesson"] == ["2026-09-21"], "keep from this Monday, drop Sunday before"
assert out[0]["start"] == "09:00" and out[0]["note"] == ""

clubs = [r for r in out if r["course"] == "Club meeting"]
assert [r["date"] for r in clubs] == ["2026-10-20", "2026-11-03"], "weekly repeat minus the exdate"
assert all(r["start"] == "17:00" and r["end"] == "19:00" for r in clubs), "wall-clock time kept across DST (25 Oct)"
c = clubs[0]
assert c["rooms"] == ["Lab. e Estudo de Jogos - Tech Lab (Oriente)"], "public places only, by their IADE name"
assert c["teachers"] == ["Prof. Cláudia"] and c["groups"] == ["RobotClub"] and c["type"] == "Club"
assert c["layer"] == "booking" and c["note"] == "Bring laptops" and c["programmes"] == [] and c["degrees"] == []

f = next(r for r in out if r["course"] == "Open day")
assert f["rooms"] == ["Aula Magna"] and f["layer"] == "event" and f["teachers"] == [] and f["groups"] == []
assert f["start"] == "10:00" and f["note"] == ""

try:
    export.assert_whitelist([out[0] | {"email": "x@example.com"}])
except AssertionError:
    pass
else:
    raise SystemExit("allowlist let an extra key through")

text = export.render(out)
assert text.startswith("[\n{") and text.endswith("}\n]\n") and json.loads(text) == out
print("ok")
