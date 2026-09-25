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


def exif_orientation(path):
    """The EXIF Orientation of a JPEG (1 = upright; 5 to 8 mean turned a quarter), from its header; 1 if there is none.
    (A local model drafted this; it read the value as an offset, fixed.)"""
    try:
        with open(path, "rb") as f:
            data = f.read(65536)
    except OSError:
        return 1
    t = data.find(b"Exif\0\0") + 6
    order = {b"II": "little", b"MM": "big"}.get(data[t:t + 2]) if t >= 6 else None
    if not order:
        return 1
    num = lambda at, n=2: int.from_bytes(data[t + at:t + at + n], order)  # noqa: E731
    ifd = num(4, 4)
    for e in range(ifd + 2, ifd + 2 + 12 * num(ifd), 12):
        if num(e) == 0x0112:  # Orientation: a short, stored inside the entry
            return num(e + 8) or 1
    return 1


def media_row(name, size, info):
    """A tv_media row from ffprobe's JSON (empty dict if ffprobe couldn't read the file)."""
    ext = Path(name).suffix.lower()
    kind = "photo" if ext in PHOTO or ext in {".gif", ".heic", ".bmp", ".tif", ".tiff"} else "video"
    v = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), None)
    dur = info.get("format", {}).get("duration")
    playable = bool(v) and (ext in PHOTO or (ext in VIDEO and v.get("codec_name") in CODECS))
    v = v or {}
    # phones store portrait pictures landscape plus a "turn a quarter" tag; the TV shows them turned, so swap
    turn = info.get("exif_orientation") in (5, 6, 7, 8) or \
        any(abs(round(float(d.get("rotation", 0)))) % 180 == 90 for d in v.get("side_data_list", [])) or \
        abs(int(float(v.get("tags", {}).get("rotate", 0) or 0))) % 180 == 90
    w, h = (v.get("height"), v.get("width")) if turn else (v.get("width"), v.get("height"))
    return {"name": name, "kind": kind, "width": w, "height": h,
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


def link_events(slides, activities, day):
    """Pages linked to a schedule activity take that activity's slot today as their dates and times; with no
    approved occurrence today (cancelled, deleted, another day) they don't play."""
    acts = {a["id"]: a for a in activities}
    out = []
    for s in slides:
        if not s.get("activity_id"):
            out.append(s)
            continue
        a = acts.get(s["activity_id"])
        slot = occurrences(a, day, day)[:1] if a and a["status"] == "approved" else []
        if not slot:
            out.append(s | {"active": False})
            continue
        start, end = slot[0]
        out.append(s | {"starts_on": day.isoformat(), "ends_on": day.isoformat(), "from_time": f"{start:%H:%M:%S}",
                        "to_time": f"{end:%H:%M:%S}" if end.date() == start.date() else "23:59:59"})
    return out


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
    info = json.loads(r.stdout or "{}")
    if Path(path).suffix.lower() in {".jpg", ".jpeg"}:
        info["exif_orientation"] = exif_orientation(path)
    return info


# Drafted by a local model (Qwen3-Coder 30B on Unsloth Studio).
def probe_cached(path, cache):
    """ffprobe's JSON for a file, re-probed only when its size or modification time changed.
    cache: dict name -> {"size", "mtime", "info"}, updated in place (main saves it as JSON between runs)."""
    name = path.name
    stat = path.stat()
    size, mtime = stat.st_size, stat.st_mtime
    if name not in cache or cache[name]["size"] != size or cache[name]["mtime"] != mtime:
        info = probe(path)
        cache[name] = {"size": size, "mtime": mtime, "info": info}
    return cache[name]["info"]



def write_qr(qr_slides):
    import segno
    (OUT / "qr").mkdir(parents=True, exist_ok=True)
    for s in qr_slides:
        segno.make(s["url"], error="m").save(OUT / "qr" / f"{s['id']}.svg", kind="svg", scale=10, border=2)


def main():
    db = connect()
    now = datetime.now(TZ)
    REND.mkdir(parents=True, exist_ok=True)
    for junk in [*MEDIA.glob("._*"), *MEDIA.glob(".DS_Store")]:  # what a Mac leaves on a network share
        junk.unlink(missing_ok=True)
    files = [p for p in sorted(MEDIA.iterdir()) if p.is_file() and not p.name.startswith(".")]
    cache_file = OUT / "probe-v2.json"  # v2: photos carry their EXIF orientation
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    media = [media_row(p.name, p.stat().st_size, probe_cached(p, cache)) for p in files]
    OUT.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps({p.name: cache[p.name] for p in files}))  # forget deleted files
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
                                      "from_time,to_time,fullscreen,takeover,activity_id",
                                      "order": "position,id"})
    activities = select(db, "activities", {"select": "id,title,place_ids,location_text,starts_at,ends_at,rrule,exdates,public_note",
                                           "status": "eq.approved", "layer": "eq.event", "order": "id"})
    linked_ids = sorted({s["activity_id"] for s in slides if s.get("activity_id")})
    linked = select(db, "activities", {"select": "id,status,starts_at,ends_at,rrule,exdates", "id": f"in.({','.join(map(str, linked_ids))})",
                                       "order": "id"}) if linked_ids else []
    slides = link_events(slides, linked, now.date())
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
