# TV showcase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lab TV page served by the edge node: the schedule column (two rooms) beside a carousel of staff-managed slides (media, bios, QR, text) plus automatic events, QR codes and 3 random anonymous ideas; managed from a new TV screen in the office.

**Architecture:** Supabase holds `tv_media` (written by the node) and `tv_slides` (written by staff). `scripts/tv.py` runs on the node every minute: probes `~/tv-media` with ffprobe, syncs `tv_media`, and writes `~/tv-out/tv.json` with the finished, public-safe playlist. nginx on the node serves `apps/tv/index.html` (plain HTML/JS, no build), the media, `tv.json` and `all.json` at `http://192.168.1.131/tv/`. Samba shares `~/tv-media` for adding files.

**Tech Stack:** Postgres/Supabase (RLS, pgTAP via `scripts/sqltest.py`), Python 3.11 + uv (`segno` for QR), ffprobe, nginx, Samba, vanilla JS, Flutter web office.

**Spec:** `docs/superpowers/specs/2026-09-24-tv-showcase-design.md`

## Global Constraints

- No Docker. Python through `uv` only.
- The database is reached over HTTPS only (PostgREST; migrations and tests through `scripts/sqltest.py`).
- New tables: staff only through `is_staff()` RLS, no anon grants.
- `tv.json` never carries emails, student names, original idea text, purposes or contact links. Ideas: AI title and summary only, anonymous.
- TV slide order: manual slides (by position, then id), events (next 14 days), Book me QR, Idea hub QR, then 3 random ideas (picked by the TV each loop).
- Default seconds 10; videos play once, muted, to their end; a failing video moves on after 2 s.
- Playable: `.mp4`/`.m4v`/`.webm` with h264, vp8, vp9 or av1 video; `.jpg`/`.jpeg`/`.png`/`.webp` images.
- Update the matching doc in the same commit as any behaviour, command, schema or URL change.

---

### Task 1: Database tables

**Files:**
- Create: `supabase/migrations/20260924200000_tv_showcase.sql`
- Test: `supabase/tests/database/06_tv.test.sql`

**Interfaces:**
- Produces: tables `tv_media(name text pk, kind, width, height, seconds, bytes, playable)` and `tv_slides(id, kind, title, body, media_name, url, seconds, position, starts_on, ends_on, active, created_at)`.

- [ ] **Step 1: Write the test** `supabase/tests/database/06_tv.test.sql`:

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

select ok((select bool_and(relrowsecurity) from pg_class where relname in ('tv_media', 'tv_slides')), 'RLS on both TV tables');
select ok(not has_table_privilege('anon', 'tv_media', 'select') and not has_table_privilege('anon', 'tv_slides', 'select'),
          'anon reads no TV table');
select ok(not has_table_privilege('authenticated', 'tv_media', 'insert')
          and not has_table_privilege('authenticated', 'tv_media', 'delete'), 'only the node (service role) writes tv_media');

insert into tv_media (name, kind, width, height, playable) values ('arm.mp4', 'video', 1920, 1080, true);
insert into tv_slides (kind, title, media_name) values ('media', 'Robot arm', 'arm.mp4');
delete from tv_media where name = 'arm.mp4';
select is((select media_name from tv_slides where title = 'Robot arm'), null, 'a deleted file leaves its slide without media');
select throws_like($$ insert into tv_slides (kind, title) values ('qr', 'No link') $$, '%tv_slides%check%',
                   'a QR slide needs a link');
select throws_like($$ insert into tv_slides (kind, title, starts_on, ends_on) values ('text', 'x', '2026-10-02', '2026-10-01') $$,
                   '%tv_slides%check%', 'the end date is not before the start date');

select * from finish();
```

- [ ] **Step 2: Run it to see it fail**

Run: `uv run python scripts/sqltest.py`
Expected: 06_tv fails (relation "tv_media" does not exist).

- [ ] **Step 3: Write the migration** `supabase/migrations/20260924200000_tv_showcase.sql`:

```sql
-- TV showcase: the edge node's media files and the staff's carousel slides. Staff only, like the other tables.

create table tv_media (   -- written by the node (scripts/tv.py) every minute
  name     text primary key,
  kind     text not null check (kind in ('video', 'photo')),
  width    int,
  height   int,
  seconds  numeric,
  bytes    bigint not null default 0,
  playable boolean not null default false
);

create table tv_slides (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('media', 'bio', 'qr', 'text')),
  title      text,
  body       text,
  media_name text references tv_media (name) on delete set null on update cascade,
  url        text,
  seconds    int not null default 10 check (seconds > 0),
  position   int not null default 0,
  starts_on  date,
  ends_on    date,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  check (kind <> 'qr' or url is not null),
  check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

-- ponytail: tv_media is not audited; the node rewrites it every minute and the files themselves are the record.
create trigger audit after insert or update or delete on tv_slides for each row execute function audit();

alter table tv_media enable row level security;
alter table tv_slides enable row level security;
create policy staff_all on tv_media for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_all on tv_slides for all to authenticated using (is_staff()) with check (is_staff());
revoke all on tv_media, tv_slides from anon;
revoke insert, update, delete, truncate on tv_media from authenticated;
```

- [ ] **Step 4: Push the migration and run all database tests**

Run: `uv run python scripts/sqltest.py`
Expected: every file passes, 06_tv 6/6.

- [ ] **Step 5: Commit** (with `docs/ARCHITECTURE.md` gaining the two tables in its data model list)

```bash
git add supabase/migrations/20260924200000_tv_showcase.sql supabase/tests/database/06_tv.test.sql docs/ARCHITECTURE.md
git commit -m "TV showcase: tv_media and tv_slides tables, staff only"
```

---

### Task 2: Node job `scripts/tv.py`

**Files:**
- Create: `scripts/tv.py`
- Test: `tests/test_tv.py`
- Modify: `pyproject.toml` (add `segno`), `uv.lock`

**Interfaces:**
- Consumes: `db.connect/select/request`, `export.occurrences(a, first, last)`, `timetable_parse.TZ`.
- Produces: `media_row(name, size, info) -> dict`, `in_window(slide, day) -> bool`, `event_slides(activities, places, today) -> list`, `build(slides, media, events, ideas, generated) -> dict`, `assert_public(tv)`; writes `~/tv-out/tv.json` and `~/tv-out/qr/*.svg`.

- [ ] **Step 1: Write the test** `tests/test_tv.py`:

```python
"""Run: uv run python tests/test_tv.py"""
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import tv  # noqa: E402

# playable check from ffprobe output
h264 = {"streams": [{"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080}], "format": {"duration": "12.34"}}
hevc = {"streams": [{"codec_type": "video", "codec_name": "hevc", "width": 3840, "height": 2160}], "format": {"duration": "5"}}
jpg = {"streams": [{"codec_type": "video", "codec_name": "mjpeg", "width": 800, "height": 1000}], "format": {}}
assert tv.media_row("arm.mp4", 10, h264) == {"name": "arm.mp4", "kind": "video", "width": 1920, "height": 1080,
                                             "seconds": 12.3, "bytes": 10, "playable": True}
assert tv.media_row("phone.mov", 10, hevc)["playable"] is False, ".mov is not played"
assert tv.media_row("uhd.mp4", 10, hevc)["playable"] is False, "HEVC doesn't play in Chrome on Linux"
assert tv.media_row("me.JPG", 5, jpg) | {} == {"name": "me.JPG", "kind": "photo", "width": 800, "height": 1000,
                                             "seconds": None, "bytes": 5, "playable": True}
assert tv.media_row("broken.png", 5, {})["playable"] is False, "unreadable file"

# date window
day = date(2026, 10, 1)
assert tv.in_window({"active": True, "starts_on": None, "ends_on": None}, day)
assert tv.in_window({"active": True, "starts_on": "2026-10-01", "ends_on": "2026-10-01"}, day)
assert not tv.in_window({"active": False, "starts_on": None, "ends_on": None}, day)
assert not tv.in_window({"active": True, "starts_on": "2026-10-02", "ends_on": None}, day)
assert not tv.in_window({"active": True, "starts_on": None, "ends_on": "2026-09-30"}, day)

# playlist
media = [tv.media_row("arm.mp4", 10, h264), tv.media_row("me.jpg", 5, jpg), tv.media_row("uhd.mp4", 1, hevc)]
base = {"title": None, "body": None, "media_name": None, "url": None, "seconds": 10, "starts_on": None, "ends_on": None,
        "active": True}
slides = [
    base | {"id": 5, "position": 2, "kind": "text", "title": "Welcome", "body": "Open lab on Fridays"},
    base | {"id": 3, "position": 1, "kind": "media", "title": "Robot arm", "media_name": "arm.mp4"},
    base | {"id": 4, "position": 1, "kind": "bio", "title": "Andrey Dyakov", "body": "Lab technician", "media_name": "me.jpg"},
    base | {"id": 6, "position": 3, "kind": "media", "media_name": "uhd.mp4"},       # unplayable: skipped
    base | {"id": 7, "position": 4, "kind": "media", "media_name": None},            # file deleted: skipped
    base | {"id": 8, "position": 5, "kind": "qr", "title": "Instagram", "url": "https://instagram.com/x"},
    base | {"id": 9, "position": 6, "kind": "text", "title": "Old", "ends_on": "2026-09-01"},  # expired: skipped
]
places = [{"id": 1, "name": "Tech Lab", "iade_name": "Lab. e Estudo de Jogos - Tech Lab (Oriente)", "public": True}]
fair = {"id": 2, "title": "Open day", "layer": "event", "place_ids": [1], "location_text": None,
        "starts_at": "2026-10-02T09:00:00+00:00", "ends_at": "2026-10-02T12:00:00+00:00", "rrule": None, "exdates": [],
        "public_note": "Everyone welcome"}
late = fair | {"id": 3, "title": "Too far", "starts_at": "2026-11-20T09:00:00+00:00", "ends_at": "2026-11-20T10:00:00+00:00"}
events = tv.event_slides([fair, late], places, day)
assert events == [{"kind": "event", "title": "Open day", "when": "Fri 2 Oct · 10:00–13:00",
                   "place": "Lab. e Estudo de Jogos - Tech Lab (Oriente)", "body": "Everyone welcome", "seconds": 10}], events
ideas = [{"ai_title": "Micro robot arm", "ai_summary": "An ESP32 arm."}, {"ai_title": None, "ai_summary": None}]
out = tv.build(slides, media, events, ideas, day, "2026-10-01T10:00:00+01:00")
kinds = [(s["kind"], s["title"]) for s in out["slides"]]
assert kinds == [("media", "Robot arm"), ("bio", "Andrey Dyakov"), ("text", "Welcome"), ("qr", "Instagram"),
                 ("event", "Open day"), ("qr", "Book a consultation"), ("qr", "Share a project idea")], kinds
arm, bio = out["slides"][0], out["slides"][1]
assert arm["src"] == "media/arm.mp4" and arm["video"] and (arm["w"], arm["h"]) == (1920, 1080)
assert bio["src"] == "media/me.jpg" and not bio["video"]
assert out["slides"][3]["src"] == "qr/8.svg"
assert out["ideas"] == [{"title": "Micro robot arm", "summary": "An ESP32 arm."}], "normalised ideas only, no names"
assert tv.build([base | {"id": 1, "position": 0, "kind": "media", "media_name": "a b.mp4"}],
                [tv.media_row("a b.mp4", 1, h264)], [], [], day, "")["slides"][0]["src"] == "media/a%20b.mp4"

tv.assert_public(out)
try:
    tv.assert_public(out | {"ideas": [{"title": "x", "summary": "y", "name": "Ana"}]})
except AssertionError:
    pass
else:
    raise SystemExit("assert_public let a name through")
print("ok")
```

- [ ] **Step 2: Run it to see it fail**

Run: `uv run python tests/test_tv.py`
Expected: `ModuleNotFoundError: No module named 'tv'`.

- [ ] **Step 3: Add segno** — `uv add segno`

- [ ] **Step 4: Write** `scripts/tv.py`:

```python
"""TV showcase job (edge node, every minute): sync the media folder to tv_media and write the TV playlist.

Usage: uv run python scripts/tv.py
Reads ~/tv-media (TV_MEDIA), writes ~/tv-out/tv.json and ~/tv-out/qr/*.svg (TV_OUT); nginx serves both, see
docs/edge-node.md. Runs with the service key, so it selects explicit columns and assert_public() checks the output:
the TV shows only public fields, and ideas only as the AI's anonymous title and summary.
"""
import json
import os
import shutil
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote

from db import connect, request, select
from export import occurrences
from timetable_parse import TZ

ROOT = Path(__file__).resolve().parent.parent
MEDIA = Path(os.environ.get("TV_MEDIA", Path.home() / "tv-media"))
OUT = Path(os.environ.get("TV_OUT", Path.home() / "tv-out"))
PHOTO = {".jpg", ".jpeg", ".png", ".webp"}
VIDEO = {".mp4", ".m4v", ".webm"}
CODECS = {"h264", "vp8", "vp9", "av1"}  # what Chromium on Linux plays without licensed decoders
EVENT_DAYS = 14
SLIDE_KEYS = {"kind", "title", "body", "seconds", "src", "video", "w", "h", "when", "place"}


def media_row(name, size, info):
    """A tv_media row from ffprobe's JSON (empty dict if ffprobe couldn't read the file)."""
    ext = Path(name).suffix.lower()
    kind = "photo" if ext in PHOTO or ext in {".gif", ".heic", ".bmp", ".tif", ".tiff"} else "video"
    v = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), None)
    dur = info.get("format", {}).get("duration")
    playable = bool(v) and (ext in PHOTO or (ext in VIDEO and v.get("codec_name") in CODECS))
    return {"name": name, "kind": kind, "width": (v or {}).get("width"), "height": (v or {}).get("height"),
            "seconds": round(float(dur), 1) if kind == "video" and dur else None, "bytes": size, "playable": playable}


def in_window(s, day):
    d = day.isoformat()
    return s["active"] and (not s["starts_on"] or s["starts_on"] <= d) and (not s["ends_on"] or s["ends_on"] >= d)


def event_slides(activities, places, today):
    names = {p["id"]: p["iade_name"] or p["name"] for p in places if p["public"]}
    out = []
    for a in activities:
        place = ", ".join(names[p] for p in a["place_ids"] if p in names) or a.get("location_text") or ""
        for s, e in occurrences(a, today, today + timedelta(days=EVENT_DAYS)):
            out.append((s, {"kind": "event", "title": a["title"], "when": f"{s:%a} {s.day} {s:%b} · {s:%H:%M}–{e:%H:%M}",
                            "place": place, "body": a.get("public_note") or "", "seconds": 10}))
    return [slide for _s, slide in sorted(out, key=lambda x: x[0])]


def build(slides, media, events, ideas, day, generated):
    files = {m["name"]: m for m in media if m["playable"]}
    out = []
    for s in sorted(slides, key=lambda s: (s["position"], s["id"])):
        m = files.get(s["media_name"] or "")
        if not in_window(s, day) or (s["kind"] == "media" and not m):
            continue
        slide = {"kind": s["kind"], "title": s["title"] or "", "body": s["body"] or "", "seconds": s["seconds"]}
        if m:
            slide |= {"src": "media/" + quote(m["name"]), "video": m["kind"] == "video", "w": m["width"], "h": m["height"]}
        if s["kind"] == "qr":
            slide["src"] = f"qr/{s['id']}.svg"
        out.append(slide)
    out += events
    out += [{"kind": "qr", "src": "qr/book.svg", "title": "Book a consultation", "body": "", "seconds": 10},
            {"kind": "qr", "src": "qr/ideas.svg", "title": "Share a project idea", "body": "", "seconds": 10}]
    return {"generated": generated, "slides": out,
            "ideas": [{"title": i["ai_title"], "summary": i["ai_summary"]} for i in ideas if i["ai_title"] and i["ai_summary"]]}


def assert_public(tv):
    for s in tv["slides"]:
        assert set(s) <= SLIDE_KEYS, f"slide has forbidden keys: {sorted(set(s) - SLIDE_KEYS)}"
    for i in tv["ideas"]:
        assert set(i) == {"title", "summary"}, f"idea has forbidden keys: {sorted(set(i) - {'title', 'summary'})}"


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
                       capture_output=True, text=True, timeout=60)
    return json.loads(r.stdout or "{}")


def write_qr(qr_slides):
    import segno
    (OUT / "qr").mkdir(parents=True, exist_ok=True)
    for f in (ROOT / "apps/site/web/qr").glob("*.svg"):
        shutil.copy(f, OUT / "qr" / f.name)
    for s in qr_slides:
        segno.make(s["url"], error="m").save(OUT / "qr" / f"{s['id']}.svg", kind="svg", scale=10, border=2)


def main():
    db = connect()
    now = datetime.now(TZ)
    MEDIA.mkdir(parents=True, exist_ok=True)
    media = [media_row(p.name, p.stat().st_size, probe(p)) for p in sorted(MEDIA.iterdir())
             if p.is_file() and not p.name.startswith(".")]
    known = {r["name"] for r in select(db, "tv_media", {"select": "name", "order": "name"})}
    if media:
        request(db, "POST", "tv_media", {"on_conflict": "name"}, media,
                {"Prefer": "resolution=merge-duplicates,return=minimal"})
    for name in known - {m["name"] for m in media}:
        request(db, "DELETE", "tv_media", {"name": f"eq.{name}"}, headers={"Prefer": "return=minimal"})
    slides = select(db, "tv_slides", {"select": "id,kind,title,body,media_name,url,seconds,position,starts_on,ends_on,active",
                                      "order": "position,id"})
    activities = select(db, "activities", {"select": "id,title,place_ids,location_text,starts_at,ends_at,rrule,exdates,public_note",
                                           "status": "eq.approved", "layer": "eq.event", "order": "id"})
    places = select(db, "places", {"select": "id,name,iade_name,public", "order": "id"})
    ideas = select(db, "ideas", {"select": "ai_title,ai_summary", "status": "eq.approved", "ai_title": "not.is.null",
                                 "order": "id"})
    tv = build(slides, media, event_slides(activities, places, now.date()), ideas, now.date(), now.isoformat(timespec="seconds"))
    assert_public(tv)
    write_qr([s for s in slides if s["kind"] == "qr" and s["url"]])
    tmp = OUT / "tv.json.tmp"
    tmp.write_text(json.dumps(tv, ensure_ascii=False), encoding="utf-8")
    tmp.replace(OUT / "tv.json")  # atomic: the TV never reads half a file
    print(f"media {len(media)}, slides {len(tv['slides'])}, ideas {len(tv['ideas'])}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the test** — `uv run python tests/test_tv.py` → `ok`. Then all: `for t in tests/test_*.py; do uv run python "$t"; done`.

- [ ] **Step 6: Commit**

```bash
git add scripts/tv.py tests/test_tv.py pyproject.toml uv.lock
git commit -m "TV showcase: node job syncs the media folder and writes the public playlist"
```

---

### Task 3: TV page `apps/tv/index.html`

**Files:**
- Create: `apps/tv/index.html`
- Test: `tests/check_tv_page.py` (Playwright on system Chrome; not in CI, which has no display server set up for it)

**Interfaces:**
- Consumes: `tv.json` (Task 2 shape) and `data/all.json` (export shape), same origin.
- Produces: the page nginx serves at `/tv/`.

- [ ] **Step 1: Write the check** `tests/check_tv_page.py`:

```python
"""Browser check of apps/tv/index.html with sample data. Run: uv run --with playwright python tests/check_tv_page.py"""
import json
import shutil
import tempfile
import threading
from datetime import date
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
LAB, MAC = "Lab. e Estudo de Jogos - Tech Lab (Oriente)", "Sala 017 Mac 1 (Oriente)"
d = Path(tempfile.mkdtemp())
shutil.copy(ROOT / "apps/tv/index.html", d / "index.html")
(d / "data").mkdir()
(d / "media").mkdir()
(d / "media/tall.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="800"><rect width="400" height="800" fill="#b3261e"/></svg>')
today = date.today().isoformat()
lesson = {"date": today, "start": "00:00", "end": "23:59", "course": "VR Development", "groups": [], "teachers": ["José"],
          "type": "P", "rooms": [LAB], "programmes": [], "degrees": [], "layer": "lesson", "note": ""}
(d / "data/all.json").write_text(json.dumps([lesson, lesson | {"course": "Mac lab", "rooms": [MAC], "layer": "booking"}]))
(d / "tv.json").write_text(json.dumps({"generated": "", "ideas": [{"title": "Micro robot arm", "summary": "An ESP32 arm."}],
    "slides": [{"kind": "media", "src": "media/tall.svg", "video": False, "w": 400, "h": 800, "title": "Tall photo", "body": "", "seconds": 1},
               {"kind": "text", "title": "Welcome", "body": "Open lab on Fridays", "seconds": 1}]}))
server = ThreadingHTTPServer(("127.0.0.1", 0), partial(SimpleHTTPRequestHandler, directory=str(d)))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}/index.html?room={LAB}&room={MAC}"

with sync_playwright() as p:
    page = p.chromium.launch(channel="chrome").new_page(viewport={"width": 1920, "height": 1080})
    page.goto(url)
    page.wait_for_selector("#frame img")
    heads = page.locator("#schedule h2").all_text_contents()
    assert heads == ["Lab. e Estudo de Jogos - Tech Lab", "Sala 017 Mac 1"], heads
    assert "VR Development" in page.inner_text("#schedule") and page.locator("#schedule article.booking.now").count() == 1
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 0.5) < 0.02, f"frame follows the photo's 1:2 shape: {box}"
    aside = page.locator("#schedule").bounding_box()
    assert 0.3 < aside["width"] / 1920 < 0.37, f"schedule column is a third: {aside}"
    page.wait_for_selector("#frame h1:has-text('Welcome')", timeout=4000)
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 16 / 9) < 0.02, f"text slides are 16:9: {box}"
    page.wait_for_selector("#frame h1:has-text('Micro robot arm')", timeout=4000)
    assert "updated" in page.inner_text("footer")
server.shutdown()
print("ok")
```

- [ ] **Step 2: Run it to see it fail** — `uv run --with playwright python tests/check_tv_page.py` → FileNotFoundError for `apps/tv/index.html`.

- [ ] **Step 3: Write** `apps/tv/index.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lab TV</title>
<!-- Showcase TV, served by the edge node (docs/edge-node.md): schedule column + carousel. No build step. -->
<style>
:root { --fg: #1a1a1a; --muted: #666; --bg: #fafaf7; --card: #fff; --line: #e3e1da; --accent: #b3261e;
        --booking: #1e5cb3; --event: #1eb350; --mat: #efece4; --frame: #d9d5ca; }
* { box-sizing: border-box; }
html { font-size: clamp(14px, 1.05vw, 40px); }
body { margin: 0; height: 100vh; display: grid; grid-template-columns: 1fr 2fr; grid-template-rows: 1fr auto;
       font: 1rem/1.35 system-ui, sans-serif; color: var(--fg); background: var(--bg); overflow: hidden; }
#schedule { padding: 1.2rem 1.4rem; border-right: 1px solid var(--line); overflow: hidden; display: flex; flex-direction: column; gap: 1rem; }
#schedule .day { display: flex; justify-content: space-between; align-items: baseline; color: var(--muted); }
#schedule .clock { font-size: 2rem; font-weight: 600; color: var(--fg); font-variant-numeric: tabular-nums; }
#schedule section { flex: 1; min-height: 0; overflow: hidden; }
#schedule h2 { margin: 0 0 .5rem; font-size: 1.1rem; letter-spacing: .04em; text-transform: uppercase; }
article { margin: 0 0 .45rem; padding: .45rem .7rem; background: var(--card); border: 1px solid var(--line); border-radius: 8px; }
article p { margin: 0; }
article .time { font-weight: 600; font-variant-numeric: tabular-nums; }
article .who { color: var(--muted); font-size: .85rem; }
article.booking { border-left: 4px solid var(--booking); }
article.event { border-left: 4px solid var(--event); }
article.past { opacity: .4; }
article.now { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent); }
.empty { color: var(--muted); }
#stage { position: relative; background: var(--mat); display: flex; align-items: center; justify-content: center; }
/* passe-partout: the mat is the stage, the frame's opening takes the slide's shape */
#frame { background: var(--card); box-shadow: 0 0 0 .35rem #fff, 0 0 0 calc(.35rem + 1px) var(--frame), 0 .8rem 2rem rgb(0 0 0 / .12);
         display: flex; overflow: hidden; }
#frame img, #frame video { width: 100%; height: 100%; object-fit: contain; background: #000; display: block; }
#frame.bio img, #frame.qr img { width: auto; max-width: 45%; object-fit: cover; background: none; }
#frame.qr img { object-fit: contain; padding: 2rem; }
#frame .text { flex: 1; padding: 3rem; display: flex; flex-direction: column; justify-content: center; gap: .8rem; }
#frame h1 { margin: 0; font-size: 3rem; line-height: 1.1; }
#frame .body { font-size: 1.6rem; color: var(--muted); white-space: pre-line; }
#frame .when { font-size: 1.6rem; color: var(--event); font-weight: 600; }
#frame .place { font-size: 1.3rem; color: var(--muted); }
#frame.idea .when { color: var(--accent); }
#caption { position: absolute; bottom: 1.2rem; left: 0; right: 0; text-align: center; font-size: 1.3rem; color: var(--muted); }
footer { grid-column: 1 / -1; padding: .2rem 1.4rem; font-size: .75rem; color: var(--muted); border-top: 1px solid var(--line); }
</style>
</head>
<body>
<aside id="schedule"></aside>
<main id="stage"><div id="frame"></div><p id="caption"></p></main>
<footer></footer>
<script>
const DEFAULT_ROOM = 'Lab. e Estudo de Jogos - Tech Lab (Oriente)';
const rooms = new URLSearchParams(location.search).getAll('room');
if (!rooms.length) rooms.push(DEFAULT_ROOM);
let lessons = [], tv = { slides: [], ideas: [] }, updated = null, queue = [], timer = null, current = null;

const pad = n => String(n).padStart(2, '0');
const iso = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const hm = d => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
};
const get = async url => {
  const r = await fetch(url, { cache: 'no-store' });
  if (!r.ok) throw new Error(`${url}: ${r.status}`);
  return r.json();
};

async function load() {  // keep the last good copy when a reload fails
  try { lessons = await get('data/all.json'); updated = new Date(); } catch (e) { console.warn(e); }
  try { tv = await get('tv.json'); updated = new Date(); } catch (e) { console.warn(e); }
  schedule();
}

function schedule() {
  const now = new Date(), day = iso(now), clock = hm(now);
  const aside = document.getElementById('schedule');
  const top = el('div', 'day');
  top.append(el('span', null, now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })), el('span', 'clock', clock));
  aside.replaceChildren(top);
  for (const room of rooms) {
    const sec = el('section');
    sec.append(el('h2', null, room.replace(/ \(Oriente\)$/, '')));
    const items = lessons.filter(l => l.date === day && l.rooms.includes(room)).sort((a, b) => a.start.localeCompare(b.start));
    if (!items.length) sec.append(el('p', 'empty', 'Free all day'));
    for (const l of items) {
      const cls = [l.layer !== 'lesson' && l.layer, l.end <= clock && 'past', l.start <= clock && l.end > clock && 'now'];
      const a = el('article', cls.filter(Boolean).join(' '));
      a.append(el('p', 'time', `${l.start}–${l.end}`), el('p', 'course', l.course));
      const who = [l.teachers.join(', '), l.groups.join(', ')].filter(Boolean).join(' · ');
      if (who) a.append(el('p', 'who', who));
      sec.append(a);
    }
    aside.append(sec);
  }
  document.querySelector('footer').textContent = updated ? `updated ${hm(updated)}` : '';
}

function playlist() {  // 3 random ideas per loop: the AI's anonymous version only
  const ideas = [...tv.ideas].sort(() => Math.random() - 0.5).slice(0, 3)
    .map(i => ({ kind: 'idea', when: 'Student idea', title: i.title, body: i.summary, seconds: 12 }));
  return [...tv.slides, ...ideas];
}

function fit() {  // the frame's opening takes the slide's shape, as large as the mat allows
  if (!current) return;
  const stage = document.getElementById('stage'), frame = document.getElementById('frame');
  const ratio = current.kind === 'media' && current.w && current.h ? current.w / current.h : 16 / 9;
  const W = stage.clientWidth * 0.86, H = stage.clientHeight * 0.8;
  const w = W / H > ratio ? H * ratio : W;
  frame.style.width = `${w}px`;
  frame.style.height = `${w / ratio}px`;
}

function next() {
  clearTimeout(timer);
  if (!queue.length) queue = playlist();
  const s = queue.shift();
  if (!s) { timer = setTimeout(next, 5000); return; }
  current = s;
  const frame = document.getElementById('frame');
  frame.className = s.kind;
  frame.replaceChildren();
  document.getElementById('caption').textContent = s.kind === 'media' ? s.title : '';
  fit();
  const skip = () => { clearTimeout(timer); timer = setTimeout(next, 2000); };
  if (s.video) {
    const v = el('video');
    Object.assign(v, { src: s.src, muted: true, autoplay: true, playsInline: true, onended: next, onerror: skip });
    frame.append(v);
    v.play().catch(skip);
    return;
  }
  if (s.src) {
    const img = el('img');
    Object.assign(img, { src: s.src, alt: s.title || '' });
    frame.append(img);
  }
  if (s.kind !== 'media') {
    const text = el('div', 'text');
    if (s.when) text.append(el('p', 'when', s.when));
    text.append(el('h1', null, s.title || ''));
    if (s.place) text.append(el('p', 'place', s.place));
    if (s.body) text.append(el('p', 'body', s.body));
    frame.append(text);
  }
  timer = setTimeout(next, (s.seconds || 10) * 1000);
}

addEventListener('resize', fit);
load().then(next);
setInterval(load, 60 * 1000);
</script>
</body>
</html>
```

- [ ] **Step 4: Run the check** — `uv run --with playwright python tests/check_tv_page.py` → `ok`.

- [ ] **Step 5: Commit**

```bash
git add apps/tv/index.html tests/check_tv_page.py
git commit -m "TV showcase: schedule column and passe-partout carousel page"
```

---

### Task 4: Office TV screen

**Files:**
- Modify: `apps/office/lib/logic.dart` (add `TvSlide`), `apps/office/lib/data.dart` (TV queries), `apps/office/lib/bookings.dart` (TV icon)
- Create: `apps/office/lib/tv_screen.dart`
- Test: `apps/office/test/logic_test.dart`

**Interfaces:**
- Consumes: tables from Task 1.
- Produces: `TvSlide` with `fromRow`, `toRow`, `showsOn(DateTime)`, `problem()`; `tvSlides()`, `tvMedia()`, `saveTvSlide(TvSlide)`, `deleteTvSlide(int)`, `reorderTvSlides(List<int>)`; `TvScreen`.

- [ ] **Step 1: Add the failing test** to `apps/office/test/logic_test.dart` (inside `main()`):

```dart
  test('TV slide: row round trip, date window, problems', () {
    final s = TvSlide.fromRow({
      'id': 3, 'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
    });
    expect(s.toRow(), {
      'kind': 'qr', 'title': 'Instagram', 'body': null, 'media_name': null, 'url': 'https://instagram.com/x',
      'seconds': 8, 'position': 2, 'starts_on': '2026-10-01', 'ends_on': '2026-10-31', 'active': true,
    });
    expect(s.showsOn(DateTime(2026, 10, 1)), isTrue);
    expect(s.showsOn(DateTime(2026, 11, 1)), isFalse);
    expect((s..active = false).showsOn(DateTime(2026, 10, 5)), isFalse);
    expect(s.problem(), isNull);
    expect(TvSlide(kind: 'qr', title: 'x', url: 'instagram.com').problem(), contains('http'));
    expect(TvSlide(kind: 'media').problem(), contains('file'));
    expect(TvSlide(kind: 'text', title: 'x', seconds: 0).problem(), contains('Seconds'));
    expect(TvSlide(kind: 'bio').problem(), contains('name'));
    expect(TvSlide(kind: 'text', title: 'x', startsOn: DateTime(2026, 10, 2), endsOn: DateTime(2026, 10, 1)).problem(),
        contains('end date'));
  });
```

- [ ] **Step 2: Run** `flutter test` (in `apps/office`) → fails: `TvSlide` isn't defined.

- [ ] **Step 3: Add to** `apps/office/lib/logic.dart`:

```dart
/// A TV carousel slide (tv_slides). The node applies the same date rule when it builds the playlist.
class TvSlide {
  TvSlide({
    this.id,
    this.kind = 'media',
    this.title = '',
    this.body = '',
    this.mediaName,
    this.url = '',
    this.seconds = 10,
    this.position = 0,
    this.startsOn,
    this.endsOn,
    this.active = true,
  });

  factory TvSlide.fromRow(Map<String, dynamic> r) => TvSlide(
        id: r['id'] as int?,
        kind: r['kind'] as String,
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        mediaName: r['media_name'] as String?,
        url: r['url'] as String? ?? '',
        seconds: r['seconds'] as int? ?? 10,
        position: r['position'] as int? ?? 0,
        startsOn: r['starts_on'] == null ? null : DateTime.parse(r['starts_on'] as String),
        endsOn: r['ends_on'] == null ? null : DateTime.parse(r['ends_on'] as String),
        active: r['active'] as bool? ?? true,
      );

  int? id;
  String kind, title, body, url;
  String? mediaName;
  int seconds, position;
  DateTime? startsOn, endsOn;
  bool active;

  Map<String, dynamic> toRow() => {
        'kind': kind,
        'title': _blank(title),
        'body': _blank(body),
        'media_name': mediaName,
        'url': _blank(url),
        'seconds': seconds,
        'position': position,
        'starts_on': startsOn == null ? null : isoDate(startsOn!),
        'ends_on': endsOn == null ? null : isoDate(endsOn!),
        'active': active,
      };

  bool showsOn(DateTime day) {
    final d = isoDate(day);
    return active &&
        (startsOn == null || isoDate(startsOn!).compareTo(d) <= 0) &&
        (endsOn == null || isoDate(endsOn!).compareTo(d) >= 0);
  }

  /// The first thing to fix before saving, or null.
  String? problem() {
    if (kind == 'media' && mediaName == null) return 'Pick a file.';
    if ((kind == 'bio' || kind == 'text') && title.trim().isEmpty) return kind == 'bio' ? 'Add a name.' : 'Add a title.';
    if (kind == 'qr' && !RegExp(r'^https?://\S+$').hasMatch(url.trim())) return 'The link must start with http:// or https://.';
    if (seconds < 1) return 'Seconds must be at least 1.';
    if (startsOn != null && endsOn != null && endsOn!.isBefore(startsOn!)) return 'The end date is before the start date.';
    return null;
  }
}
```

- [ ] **Step 4: Add to** `apps/office/lib/data.dart`:

```dart
Future<List<TvSlide>> tvSlides() async =>
    [for (final r in await db.from('tv_slides').select().order('position').order('id')) TvSlide.fromRow(r)];

/// The files the edge node reported from its shared TV folder.
Future<List<Rec>> tvMedia() async => await db.from('tv_media').select('name,kind,playable').order('name');

Future<void> saveTvSlide(TvSlide s) async {
  if (s.id == null) {
    await db.from('tv_slides').insert(s.toRow());
  } else {
    await db.from('tv_slides').update(s.toRow()).eq('id', s.id!);
  }
}

Future<void> deleteTvSlide(int id) async => await db.from('tv_slides').delete().eq('id', id);

Future<void> reorderTvSlides(List<int> ids) async =>
    await Future.wait([for (var i = 0; i < ids.length; i++) db.from('tv_slides').update({'position': i}).eq('id', ids[i])]);
```

- [ ] **Step 5: Create** `apps/office/lib/tv_screen.dart`:

```dart
// TV showcase: the slides the lab TV plays beside the schedule (docs/STAFF-GUIDE.md, "The TV").
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';

const tvAddress = 'http://192.168.1.131/tv/';
const tvFolder = 'smb://192.168.1.131/tv';
const slideKinds = {'media': 'Video or photo', 'bio': 'Bio', 'qr': 'QR code', 'text': 'Text'};

String mediaLabel(Rec m) => '${m['name']}${m['playable'] == true ? '' : " (won't play on the TV)"}';

class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  List<TvSlide>? slides;
  List<Rec> media = [];
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([tvSlides(), tvMedia()]);
      setState(() {
        slides = r[0] as List<TvSlide>;
        media = r[1] as List<Rec>;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Future<void> _reorder(int from, int to) async {
    final list = [...slides!];
    list.insert(to, list.removeAt(from));
    setState(() => slides = list);
    await _run(() => reorderTvSlides([for (final s in list) s.id!]));
  }

  String _subtitle(TvSlide s) => [
        slideKinds[s.kind]!,
        if (s.mediaName != null) s.mediaName!,
        '${s.seconds} s',
        if (s.startsOn != null || s.endsOn != null)
          '${s.startsOn == null ? '…' : isoDate(s.startsOn!)} – ${s.endsOn == null ? '…' : isoDate(s.endsOn!)}',
        if (!s.showsOn(DateTime.now())) 'not showing today',
      ].join(' · ');

  Future<void> _edit(TvSlide s) async {
    final title = TextEditingController(text: s.title), body = TextEditingController(text: s.body);
    final url = TextEditingController(text: s.url), seconds = TextEditingController(text: '${s.seconds}');
    var kind = s.kind;
    String? mediaName = s.mediaName;
    DateTime? from = s.startsOn, to = s.endsOn;
    Future<DateTime?> pick(DateTime? d) =>
        showDatePicker(context: context, initialDate: d ?? DateTime.now(), firstDate: DateTime(2026), lastDate: DateTime(2030));
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(s.id == null ? 'Add slide' : 'Edit slide'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [for (final e in slideKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => kind = v!),
              ),
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: kind == 'bio' ? 'Name' : kind == 'media' ? 'Caption (optional)' : 'Title'),
              ),
              if (kind == 'bio' || kind == 'text')
                TextField(
                  controller: body,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: kind == 'bio' ? 'Role and short bio' : 'Text'),
                ),
              if (kind == 'media' || kind == 'bio')
                DropdownButtonFormField<String?>(
                  key: ValueKey(kind),
                  initialValue: media.any((m) => m['name'] == mediaName) ? mediaName : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: kind == 'bio' ? 'Photo (optional)' : 'File from the TV folder'),
                  items: [
                    if (kind == 'bio') const DropdownMenuItem<String?>(value: null, child: Text('No photo')),
                    for (final m in media)
                      if (kind == 'media' || m['kind'] == 'photo')
                        DropdownMenuItem<String?>(value: m['name'] as String, child: Text(mediaLabel(m), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => mediaName = v),
                ),
              if (kind == 'qr') TextField(controller: url, decoration: const InputDecoration(labelText: 'Link (https://…)')),
              TextField(
                controller: seconds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seconds on screen (videos play to the end)'),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  onPressed: () async {
                    final d = await pick(from);
                    if (d != null) set(() => from = d);
                  },
                  child: Text(from == null ? 'From: now' : 'From ${isoDate(from!)}'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final d = await pick(to);
                    if (d != null) set(() => to = d);
                  },
                  child: Text(to == null ? 'Until: no end' : 'Until ${isoDate(to!)}'),
                ),
                if (from != null || to != null)
                  TextButton(onPressed: () => set(() => from = to = null), child: const Text('Clear dates')),
              ]),
            ]),
          ),
          actions: [
            if (s.id != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (action == 'delete') return _run(() => deleteTvSlide(s.id!));
    if (action != 'save') return;
    final slide = TvSlide(
      id: s.id,
      kind: kind,
      title: title.text,
      body: kind == 'bio' || kind == 'text' ? body.text : '',
      mediaName: kind == 'media' || kind == 'bio' ? mediaName : null,
      url: kind == 'qr' ? url.text.trim() : '',
      seconds: int.tryParse(seconds.text.trim()) ?? 0,
      position: s.position,
      startsOn: from,
      endsOn: to,
      active: s.active,
    );
    final problem = slide.problem();
    if (problem != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await _run(() => saveTvSlide(slide));
  }

  @override
  Widget build(BuildContext context) {
    final list = slides;
    return Scaffold(
      appBar: AppBar(title: const Text('TV'), actions: [
        IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: list == null ? null : () => _edit(TvSlide(position: list.length)),
        icon: const Icon(Icons.add),
        label: const Text('Add slide'),
      ),
      body: error != null
          ? Center(child: Text(error!))
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SelectionArea(
                      child: Text('TV: $tvAddress?room=…&room=…   ·   Files: $tvFolder (lab network)\n'
                          'After your slides the TV adds, by itself: events of the next 14 days, the Book me and '
                          'Idea hub QR codes, and 3 random approved ideas (AI version, no names). '
                          'Drag to reorder; the switch turns a slide on or off.'),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('No slides yet.'))
                        : ReorderableListView(
                            padding: const EdgeInsets.only(bottom: 88),
                            onReorderItem: _reorder,
                            children: [
                              for (final s in list)
                                ListTile(
                                  key: ValueKey(s.id),
                                  leading: Switch(
                                    value: s.active,
                                    onChanged: (v) => _run(() => saveTvSlide(s..active = v)),
                                  ),
                                  title: Text(s.title.isNotEmpty ? s.title : s.mediaName ?? slideKinds[s.kind]!),
                                  subtitle: Text(_subtitle(s)),
                                  onTap: () => _edit(s),
                                ),
                            ],
                          ),
                  ),
                ]),
    );
  }
}
```

- [ ] **Step 6: Add the TV icon** in `apps/office/lib/bookings.dart` app bar, before the Ideas icon, and import `tv_screen.dart`:

```dart
              IconButton(
                tooltip: 'TV',
                icon: const Icon(Icons.tv),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TvScreen())),
              ),
```

- [ ] **Step 7: Run** `flutter analyze && flutter test` (in `apps/office`) → no issues, all tests pass.

- [ ] **Step 8: Commit** (with the STAFF-GUIDE "The TV" section: TV icon, slide kinds, shared folder, formats, automatic slides)

```bash
git add apps/office docs/STAFF-GUIDE.md
git commit -m "Office: TV screen to manage the showcase slides"
```

---

### Task 5: Idea hub notice and seed ideas

**Files:**
- Modify: `apps/site/lib/pages/ideas_page.dart:79-80` (notice line), `docs/superpowers/specs/2026-09-24-idea-hub-design.md` (notice text)

- [ ] **Step 1: Change the notice** in `ideas_page.dart` to:

```dart
            p(classes: 'note', [.text('Your idea is saved in your lab history, visible to lab staff only; '
                'matched students see its title and your first name. Approved ideas may be shown on the lab TV '
                'without your name, in the AI\'s version.')]),
```

- [ ] **Step 2: Run** `dart analyze && dart test` (in `apps/site`) → no issues, 11 tests pass.

- [ ] **Step 3: Insert the 20 seed ideas** once (service key, from the repo root with `.env` loaded):

```bash
set -a; . ./.env; set +a
uv run python - <<'EOF'
import sys; sys.path.insert(0, "scripts")
from db import connect, request, select
db = connect()
me = select(db, "people", {"select": "id", "name": "eq.Andrey Dyakov", "is_staff": "eq.true", "order": "id"})[0]["id"]
ideas = [
 "Micro robot arm powered by an ESP32: small servos, 3D-printed parts, controlled from a phone.",
 "Automated camera slider for hyperlapses: a stepper motor moves the camera slowly along a rail while it shoots.",
 "Camera tracker that follows a person in frame: a pan-tilt head turns the camera to keep them in view (big brother is watching you).",
 "Plant watering: a soil moisture sensor and a small pump keep a plant alive on their own.",
 "Weather station with a web dashboard: ESP32 and a BME280 sensor (temperature, humidity, pressure).",
 "Reaction-time game: LEDs light up at random, press the button fast; best score on a small screen.",
 "Ultrasonic distance meter or parking sensor that beeps faster as you get closer.",
 "Lab occupancy counter: an infrared beam at the door counts people in and out.",
 "RFID tool check-out logger: tap a card to borrow or return a tool from the lab.",
 "LED matrix sign that scrolls the next Tech Lab lesson from the lab schedule.",
 "Ultrasonic theremin: move your hand to change the pitch of a buzzer or speaker.",
 "Line-following robot car with infrared sensors.",
 "Self-balancing robot on two wheels with an MPU6050 motion sensor.",
 "Wi-Fi RGB mood lamp with a WS2812 LED strip, controlled from a web page.",
 "Pomodoro timer with an OLED screen and a buzzer.",
 "Desk light that turns on by itself when a PIR sensor sees motion.",
 "MIDI controller with knobs and sliders for music software.",
 "Bluetooth gamepad for Unity games built on an ESP32.",
 "Noise-level traffic light for the lab: green, yellow, red as the room gets louder.",
 "Simon says memory game with coloured buttons, LEDs and sounds.",
]
request(db, "POST", "ideas", None, [{"person_id": me, "body": b, "status": "approved"} for b in ideas], {"Prefer": "return=minimal"})
print(len(ideas), "ideas added")
EOF
```

- [ ] **Step 4: Normalise them** with the local AI (Mac Ollama with ornith while the Studio PC is off):
`set -a; . ./.env; set +a; uv run python scripts/ideas_ai.py` → `normalised 20, approved 20, matches N`.

- [ ] **Step 5: Commit**

```bash
git add apps/site/lib/pages/ideas_page.dart docs/superpowers/specs/2026-09-24-idea-hub-design.md
git commit -m "Idea hub: notice mentions the anonymous TV showing; 20 lab seed ideas"
```

---

### Task 6: Node setup and docs

**Files:**
- Create: `scripts/tv-nginx.conf`
- Modify: `scripts/edge-setup.sh` (step 9/9), `docs/edge-node.md`, `docs/ARCHITECTURE.md`, `README.md`

- [ ] **Step 1: Write** `scripts/tv-nginx.conf` (edge-setup replaces `/home/TechLAB` with the real home):

```nginx
# Showcase TV on the lab network (docs/edge-node.md). Installed by scripts/edge-setup.sh.
server {
  listen 80 default_server;
  location = / { return 302 /tv/; }
  location /tv/ { alias /home/TechLAB/openlabtwin/apps/tv/; }
  location /tv/media/ { alias /home/TechLAB/tv-media/; }
  location /tv/qr/ { alias /home/TechLAB/tv-out/qr/; }
  location = /tv/tv.json { alias /home/TechLAB/tv-out/tv.json; add_header Cache-Control no-store; }
  location = /tv/data/all.json { alias /home/TechLAB/openlabtwin/apps/site/web/data/all.json; add_header Cache-Control no-store; }
}
```

- [ ] **Step 2: Add step 9/9** to `scripts/edge-setup.sh` (and renumber the others "x/9"), before "done", plus the cron line `* * * * *  cd $DIR && set -a && . ./.env && set +a && $HOME/.local/bin/uv run python scripts/tv.py > /dev/null 2>> \$HOME/tv.log`:

```bash
step "9/9 TV showcase (nginx serves http://<ip>/tv/, Samba shares ~/tv-media as smb://<ip>/tv)"
run sudo apt-get install -y -qq nginx-light samba ffmpeg
run mkdir -p "$HOME/tv-media" "$HOME/tv-out/qr"
run chmod o+x "$HOME"   # nginx (www-data) may pass through home, and reads only what the site file names
run sh -c "sed 's#/home/TechLAB#$HOME#g' '$DIR/scripts/tv-nginx.conf' | sudo tee /etc/nginx/sites-available/tv >/dev/null"
run sudo ln -sf /etc/nginx/sites-available/tv /etc/nginx/sites-enabled/tv
run sudo rm -f /etc/nginx/sites-enabled/default
run sudo nginx -t
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then run sudo systemctl enable --now nginx smbd; run sudo systemctl reload nginx
else run sudo service nginx reload; run sudo service smbd start; fi
if ! grep -q '^\[tv\]' /etc/samba/smb.conf; then
  run sh -c "printf '\n[tv]\n   path = $HOME/tv-media\n   valid users = $USER\n   read only = no\n   create mask = 0644\n   directory mask = 0755\n' | sudo tee -a /etc/samba/smb.conf >/dev/null"
  run sudo systemctl restart smbd
fi
if [ "$DRY" = 0 ] && ! sudo pdbedit -L 2>/dev/null | grep -q "^$USER:"; then
  echo "  Samba password for $USER (used to connect to smb://<ip>/tv):"; sudo smbpasswd -a "$USER" </dev/tty
fi
if command -v ufw >/dev/null; then for net in 192.168.1.0/24 10.208.16.0/23; do
  run sudo ufw allow from "$net" to any port 80 proto tcp; run sudo ufw allow from "$net" to any port 445 proto tcp; done; fi
```

- [ ] **Step 3: Check the script** — `bash -n scripts/edge-setup.sh && scripts/edge-setup.sh --dry-run | tail -30` (on the Mac, dry run prints the would-run lines).

- [ ] **Step 4: Docs** — `docs/edge-node.md`: a "TV showcase" section (address, shared folder, formats, `tail ~/tv.log`, `cat ~/tv-out/tv.json`); `docs/ARCHITECTURE.md`: `scripts/tv.py` and `apps/tv` in the component table, the two tables; `README.md`: the showcase TV address.

- [ ] **Step 5: Commit and push**

```bash
git add scripts/tv-nginx.conf scripts/edge-setup.sh docs README.md
git commit -m "Edge node: nginx, Samba and cron for the TV showcase"
git push
```

- [ ] **Step 6: On the node** (needs sudo, so Andrey runs it): `cd ~/openlabtwin && git pull && scripts/edge-setup.sh`. Then from the Mac: `curl -s http://192.168.1.131/tv/tv.json | head -c 300` shows slides, and `http://192.168.1.131/tv/` shows the page.
