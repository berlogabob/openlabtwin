"""TV showcase job (edge node, every minute): sync the media folder to tv_media and write the TV playlist.

Usage: uv run python scripts/tv.py
Reads ~/tv-media (TV_MEDIA), writes ~/tv-out/tv.json and ~/tv-out/qr/*.svg (TV_OUT); nginx serves both, see
docs/edge-node.md. Runs with the service key, so it selects explicit columns and assert_public() checks the output:
the TV shows only public fields, and ideas only as the AI's anonymous title and summary.
"""
import fcntl
import json
import os
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote

from db import connect, request, select
from export import occurrences
from timetable_parse import TZ

MEDIA = Path(os.environ.get("TV_MEDIA", Path.home() / "tv-media"))
OUT = Path(os.environ.get("TV_OUT", Path.home() / "tv-out"))
PHOTO = {".jpg", ".jpeg", ".png", ".webp"}
# Lighter copies of every video, so a slow TV computer (a Pi 3) can play them: height -> H.264 bit rate, no audio (the
# TV plays muted). Kept in a hidden folder inside the shared one, so nginx serves them as media/.tv/... with no change.
TIERS = {480: "1200k", 720: "2500k", 1080: "5000k"}
REND = MEDIA / ".tv"
VIDEO = {".mp4", ".m4v", ".webm"}
CODECS = {"h264", "vp8", "vp9", "av1"}  # what Chromium on Linux plays without licensed decoders
EVENT_DAYS = 14
SLIDE_KEYS = {"kind", "title", "body", "seconds", "src", "video", "w", "h", "when", "place", "length", "full", "renditions",
              "from", "to", "takeover"}


def media_row(name, size, info):
    """A tv_media row from ffprobe's JSON (empty dict if ffprobe couldn't read the file)."""
    ext = Path(name).suffix.lower()
    kind = "photo" if ext in PHOTO or ext in {".gif", ".heic", ".bmp", ".tif", ".tiff"} else "video"
    v = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), None)
    dur = info.get("format", {}).get("duration")
    playable = bool(v) and (ext in PHOTO or (ext in VIDEO and v.get("codec_name") in CODECS))
    return {"name": name, "kind": kind, "width": (v or {}).get("width"), "height": (v or {}).get("height"),
            "seconds": round(float(dur), 1) if kind == "video" and dur else None, "bytes": size, "playable": playable}


def rendition_names(m, mtime):
    """The copies a video gets: each tier up to its own height (480p always). The name carries the source's size and
    time, so replacing a file under the same name makes new copies."""
    tag = f"{m['bytes']:x}{int(mtime):x}"
    return {h: f"{Path(m['name']).stem}.{tag}.{h}p.mp4" for h in TIERS if h <= max(m["height"] or 0, 480)}


def in_window(s, day, clock=None):
    """Active, inside its dates, and (given the clock, HH:MM) inside its times of day."""
    d = day.isoformat()
    if not (s["active"] and (not s["starts_on"] or s["starts_on"] <= d) and (not s["ends_on"] or s["ends_on"] >= d)):
        return False
    start, end = (s.get("from_time") or "")[:5], (s.get("to_time") or "")[:5]
    return clock is None or ((not start or start <= clock) and (not end or clock < end))


def event_slides(activities, places, today):
    names = {p["id"]: p["iade_name"] or p["name"] for p in places if p["public"]}
    out = []
    for a in activities:
        place = ", ".join(names[p] for p in a["place_ids"] if p in names) or a.get("location_text") or ""
        for s, e in occurrences(a, today, today + timedelta(days=EVENT_DAYS)):
            out.append((s, {"kind": "event", "title": a["title"], "when": f"{s:%a} {s.day} {s:%b} · {s:%H:%M}–{e:%H:%M}",
                            "place": place, "body": a.get("public_note") or "", "seconds": 10}))
    return [slide for _s, slide in sorted(out, key=lambda x: x[0])]


def build(slides, media, events, ideas, day, generated, clock=None, renditions=None):
    """The day's playlist in the staff's order. An 'events' row expands into the events at its place; an 'ideas' row
    stays a marker the TV fills with 3 random ideas each loop. Pages carry their times of day ('from', 'to') and
    'takeover'; the TV applies them on its own clock, so an event takes over at 17:00:00, not a minute or two later.
    'takeover' and 'playing' describe the node's clock, for the office."""
    files = {m["name"]: m for m in media if m["playable"]}
    ordered = [s for s in sorted(slides, key=lambda s: (s["position"], s["id"])) if in_window(s, day)
               and not (s["kind"] == "media" and not files.get(s["media_name"] or ""))]
    live = [s for s in ordered if in_window(s, day, clock)]
    takeover = any(s.get("takeover") for s in live)

    def pages(s):
        times = {k: v for k, v in (("from", (s.get("from_time") or "")[:5]), ("to", (s.get("to_time") or "")[:5]),
                                   ("takeover", bool(s.get("takeover")))) if v}
        if s["kind"] == "events":
            return [e | {"seconds": s["seconds"] or 10} | times for e in events]
        m = files.get(s["media_name"] or "")
        slide = {"kind": s["kind"], "title": s["title"] or "", "body": s["body"] or "", "seconds": s["seconds"]} | times
        if s.get("fullscreen"):
            slide["full"] = True
        if m:
            slide |= {"src": "media/" + quote(m["name"]), "video": m["kind"] == "video", "w": m["width"], "h": m["height"],
                      "length": m["seconds"]}  # seconds None on a video: play it to the end
            if (renditions or {}).get(m["name"]):  # the TV picks the copy its computer can play smoothly
                slide["renditions"] = {str(h): "media/.tv/" + quote(f) for h, f in sorted(renditions[m["name"]].items())}
        if s["kind"] == "qr":
            slide["src"] = f"qr/{s['id']}.svg"
        return [slide]

    now = sum(len(pages(s)) for s in live if s.get("takeover") or not takeover)
    return {"generated": generated, "takeover": takeover, "playing": describe_playing(live, takeover, now),
            "slides": [x for s in ordered for x in pages(s)],
            "ideas": [{"title": i["ai_title"], "summary": i["ai_summary"]} for i in ideas if i["ai_title"] and i["ai_summary"]]}


def assert_public(tv):
    for s in tv["slides"]:
        assert set(s) <= SLIDE_KEYS, f"slide has forbidden keys: {sorted(set(s) - SLIDE_KEYS)}"
    for i in tv["ideas"]:
        assert set(i) == {"title", "summary"}, f"idea has forbidden keys: {sorted(set(i) - {'title', 'summary'})}"


def describe_playing(slides, takeover, pages):
    """What the TV plays now, for the office's status line."""
    if not takeover:
        return f"Normal loop: {pages} pages" if pages else "Nothing to play"
    on = [s for s in slides if s.get("takeover")]
    names = ", ".join(s["title"] or s["media_name"] or s["kind"] for s in on)
    until = min((s["to_time"][:5] for s in on if s.get("to_time")), default=None) or \
        min((s["ends_on"] for s in on if s.get("ends_on")), default=None)
    return f"Takeover: {names}" + (f" until {until}" if until else "")


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
                       capture_output=True, text=True, timeout=60)
    return json.loads(r.stdout or "{}")


def write_qr(qr_slides):
    import segno
    (OUT / "qr").mkdir(parents=True, exist_ok=True)
    for s in qr_slides:
        segno.make(s["url"], error="m").save(OUT / "qr" / f"{s['id']}.svg", kind="svg", scale=10, border=2)


def main():
    db = connect()
    now = datetime.now(TZ)
    REND.mkdir(parents=True, exist_ok=True)
    files = [p for p in sorted(MEDIA.iterdir()) if p.is_file() and not p.name.startswith(".")]
    media = [media_row(p.name, p.stat().st_size, probe(p)) for p in files]
    mtimes = {p.name: p.stat().st_mtime for p in files}
    wanted = {m["name"]: rendition_names(m, mtimes[m["name"]]) for m in media if m["kind"] == "video" and m["height"]}
    ready = {name: {h: f for h, f in r.items() if (REND / f).exists()} for name, r in wanted.items()}
    for m in media:
        m["playable"] = m["playable"] or bool(ready.get(m["name"]))  # an iPhone .mov plays once its copies exist
    known = {r["name"] for r in select(db, "tv_media", {"select": "name", "order": "name"})}
    if media:
        request(db, "POST", "tv_media", {"on_conflict": "name"}, media,
                {"Prefer": "resolution=merge-duplicates,return=minimal"})
    for name in known - {m["name"] for m in media}:
        request(db, "DELETE", "tv_media", {"name": f"eq.{name}"}, headers={"Prefer": "return=minimal"})
    slides = select(db, "tv_slides", {"select": "id,kind,title,body,media_name,url,seconds,position,starts_on,ends_on,active,"
                                      "from_time,to_time,fullscreen,takeover",
                                      "order": "position,id"})
    activities = select(db, "activities", {"select": "id,title,place_ids,location_text,starts_at,ends_at,rrule,exdates,public_note",
                                           "status": "eq.approved", "layer": "eq.event", "order": "id"})
    places = select(db, "places", {"select": "id,name,iade_name,public", "order": "id"})
    ideas = select(db, "ideas", {"select": "ai_title,ai_summary", "status": "eq.approved", "ai_title": "not.is.null",
                                 "order": "id"})
    tv = build(slides, media, event_slides(activities, places, now.date()), ideas, now.date(), now.isoformat(timespec="seconds"),
               now.strftime("%H:%M"), ready)
    assert_public(tv)
    write_qr([s for s in slides if s["kind"] == "qr" and s["url"]])
    tmp = OUT / "tv.json.tmp"
    tmp.write_text(json.dumps(tv, ensure_ascii=False), encoding="utf-8")
    tmp.replace(OUT / "tv.json")  # atomic: the TV never reads half a file
    heartbeat(db, {"built_at": now.isoformat(), "pages": len(tv["slides"]), "media": len(media), "takeover": tv["takeover"],
                   "playing": tv["playing"], "error": None, "error_at": None})
    print(f"media {len(media)}, slides {len(tv['slides'])}, ideas {len(tv['ideas'])}")
    transcode(wanted)  # slow: after the playlist and heartbeat are out; later runs use what it made


def transcode(wanted):
    """Make the missing copies (one run at a time: a lock) and remove copies whose source is gone or changed."""
    keep = {f for r in wanted.values() for f in r.values()}
    for f in REND.glob("*.mp4"):
        if f.name not in keep:
            f.unlink()
    with open(REND / ".lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return  # another run is transcoding
        for f in REND.glob("*.part"):
            f.unlink()
        for name, r in wanted.items():
            for h, f in sorted(r.items()):
                if (REND / f).exists():
                    continue
                part = REND / f"{f}.part"
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(MEDIA / name), "-vf", f"scale=-2:{h}", "-c:v", "libx264",
                                "-preset", "veryfast", "-profile:v", "main", "-pix_fmt", "yuv420p", "-b:v", TIERS[h],
                                "-maxrate", TIERS[h], "-bufsize", TIERS[h], "-an", "-movflags", "+faststart", "-f", "mp4", str(part)],
                               check=True, timeout=3 * 3600)
                part.replace(REND / f)


def heartbeat(db, fields):
    """The office's view of the TV (tv_status, one row): last good build, or the last error."""
    request(db, "POST", "tv_status", {"on_conflict": "id"}, [{"id": 1, **fields}],
            {"Prefer": "resolution=merge-duplicates,return=minimal"})


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 - report it to the office, then fail as before (cron logs it)
        try:
            heartbeat(connect(), {"error": f"{type(e).__name__}: {e}"[:500], "error_at": datetime.now(TZ).isoformat()})
        finally:
            raise
