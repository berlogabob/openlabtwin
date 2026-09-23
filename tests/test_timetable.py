"""Run: uv run python tests/test_timetable.py"""
import sys
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "scripts"))
import timetable  # noqa: E402
import timetable_parse as tp  # noqa: E402

# --- ported parser checks (same fixtures and asserts as iade-lab-schedule/tests/test_parse.py)
ls = tp.parse_page((HERE / "fixture_turma.html").read_text(encoding="utf-8-sig"))
got = sorted((l["date"], l["start"], l["end"]) for l in ls)
assert got == [("2026-12-14", "14:00", "16:30"), ("2026-12-15", "13:00", "17:00"), ("2026-12-16", "13:00", "17:00"),
               ("2026-12-17", "14:00", "16:30"), ("2026-12-18", "13:00", "17:00")], got
l = ls[0]
assert l["course"] == "Exploração Profissional I / Professional Exploration I"
assert l["groups"] == ["LDGL001D01", "LDGL001D02", "LDGL001D03"]
assert l["teachers"] == ["Pedro Machado", "Tânia Fernandes"]
assert l["type"] == "P"
assert l["rooms"] == ["Sala 012 (Oriente)", "Sala 013 (Oriente)", "Sala 014 (Oriente)", "Sala 015 (Oriente)"]

html = (HERE / "fixture_multiweek.html").read_text(encoding="utf-8-sig")
ms = tp.week_mondays(html)
assert len(ms) == 10 and ms[0].isoformat() == "2026-10-12" and ms[-1].isoformat() == "2026-12-14"
assert len(tp.parse_page(html)) % 10 == 0

idx = 'href="turma_A_1_20260921.html?1" href="turma_B_2_2026092120261005.html?1" href="turma_C_3_20260901.html?1"'
assert tp.find_pages(idx, datetime(2026, 9, 30).date()) == ["turma_B_2_2026092120261005.html"]

tree = """<li>IADE: Mestrado em Computação Criativa e Inteligência Artificial<ul>
<li>Ano 1<ul>
<li>IADE M-CIA 1ºS<ul>
<li>MCIA001N01<ul>
<li><a href="turma_MCIA001N01_452_20260907.html">Semanas</a></li>
<li>IADE: Licenciatura em Desenvolvimento de Jogos<ul>
<li>LDJO001D01<ul>"""
progs = tp.group_programmes(tree)
assert progs == {"MCIA001N01": "Mestrado em Computação Criativa e Inteligência Artificial",
                 "LDJO001D01": "Licenciatura em Desenvolvimento de Jogos"}, progs
assert tp.degree("Erasmus 2022") == "Other"

# --- the week starts on Monday
assert tp.monday_of(date(2026, 9, 23)) == date(2026, 9, 21)
assert tp.monday_of(date(2026, 9, 21)) == date(2026, 9, 21)

# --- rows for the lessons table
base = {"date": "2026-10-01", "start": "09:00", "end": "12:00", "course": "X", "teachers": ["T"], "type": "P",
        "rooms": ["Sala 1"], "source_url": "u"}
rows = timetable.to_rows([base | {"groups": ["G1"]}, base | {"groups": ["G2"]}], {"G1": "Mestrado em Y"})
assert len(rows) == 1, rows
r = rows[0]
assert set(r) == {"hash", "date", "start_time", "end_time", "course", "teachers", "groups", "rooms", "type",
                  "programmes", "degrees"}, r
assert r["groups"] == ["G1", "G2"] and r["programmes"] == ["Mestrado em Y"] and r["degrees"] == ["Master"]
assert r["start_time"] == "09:00" and r["end_time"] == "12:00"
assert r["hash"] == timetable.to_rows([base | {"groups": ["G9"]}], {})[0]["hash"], "hash must ignore groups"
assert r["hash"] != timetable.to_rows([base | {"groups": ["G1"], "end": "13:00"}], {})[0]["hash"]

# --- sync plan: upsert everything scraped, delete what vanished from the source
up, gone = timetable.plan_sync(["a", "b", "c"], [{"hash": "b"}, {"hash": "d"}])
assert [x["hash"] for x in up] == ["b", "d"] and gone == ["a", "c"]
print("ok")
