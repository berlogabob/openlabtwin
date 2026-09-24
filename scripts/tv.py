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
