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
    base | {"id": 10, "position": 0, "kind": "events", "title": "Upcoming events", "seconds": 8},
    base | {"id": 11, "position": 7, "kind": "ideas", "title": "Student ideas", "seconds": 12},
    base | {"id": 12, "position": 8, "kind": "ideas", "title": "Off", "active": False},
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
assert kinds == [("event", "Open day"), ("media", "Robot arm"), ("bio", "Andrey Dyakov"), ("text", "Welcome"),
                 ("qr", "Instagram"), ("ideas", "Student ideas")], kinds
assert out["slides"][0]["seconds"] == 8, "events take their row's seconds"
assert out["slides"][-1]["seconds"] == 12
arm, bio = out["slides"][1], out["slides"][2]
assert arm["src"] == "media/arm.mp4" and arm["video"] and (arm["w"], arm["h"]) == (1920, 1080) and arm["length"] == 12.3
whole = tv.build([base | {"id": 1, "position": 0, "kind": "media", "media_name": "arm.mp4", "seconds": None}], media, [], [], day, "")
assert whole["slides"][0]["seconds"] is None, "empty seconds: the TV plays the whole video"
assert bio["src"] == "media/me.jpg" and not bio["video"]
assert out["slides"][4]["src"] == "qr/8.svg"
assert out["ideas"] == [{"title": "Micro robot arm", "summary": "An ESP32 arm."}], "normalised ideas only, no names"
assert tv.build([base | {"id": 1, "position": 0, "kind": "media", "media_name": "a b.mp4"}],
                [tv.media_row("a b.mp4", 1, h264)], [], [], day, "")["slides"][0]["src"] == "media/a%20b.mp4"

# event mode: times of day, full screen, takeover
moda = base | {"id": 20, "position": 9, "kind": "text", "title": "Moda show", "from_time": "17:00:00", "to_time": "20:00:00",
               "fullscreen": True, "takeover": True}
assert tv.in_window(moda, day, "17:00") and tv.in_window(moda, day, "19:59") and not tv.in_window(moda, day, "20:00")
assert not tv.in_window(moda, day, "16:59") and tv.in_window(moda, day), "no clock: times are not checked"
before = tv.build(slides + [moda], media, events, ideas, day, "", "16:30")
during = tv.build(slides + [moda], media, events, ideas, day, "", "17:05")
assert not before["takeover"] and during["takeover"], "the node's view, for the office"
assert during["playing"] == "Takeover: Moda show until 20:00" and before["playing"].startswith("Normal loop")
assert before["slides"] == during["slides"], "the whole day either way: the TV applies the times on its own clock"
assert before["slides"][-1] == {"kind": "text", "title": "Moda show", "body": "", "seconds": 10, "from": "17:00", "to": "20:00",
                                "takeover": True, "full": True}, before["slides"][-1]
tv.assert_public(during)
tv.assert_public(out)
try:
    tv.assert_public(out | {"ideas": [{"title": "x", "summary": "y", "name": "Ana"}]})
except AssertionError:
    pass
else:
    raise SystemExit("assert_public let a name through")
print("ok")

# what the TV is playing, for the office (heartbeat)
reel = base | {"id": 30, "kind": "media", "title": None, "media_name": "reel.m4v"}
assert tv.describe_playing([moda], True, 1) == "Takeover: Moda show until 20:00"
assert tv.describe_playing([moda | {"to_time": None, "ends_on": "2026-10-01"}], True, 1) == "Takeover: Moda show until 2026-10-01"
assert tv.describe_playing([moda | {"title": None, "media_name": "proto.mp4"}, moda | {"title": "Poster"}], True, 2) == \
    "Takeover: proto.mp4, Poster until 20:00"
assert tv.describe_playing([reel], False, 7) == "Normal loop: 7 pages"
assert tv.describe_playing([], False, 0) == "Nothing to play"
assert tv.describe_playing([moda | {"to_time": None, "ends_on": "2026-10-09"}, moda | {"to_time": None, "ends_on": "2026-10-02"}],
                           True, 2).endswith("until 2026-10-02"), "the earliest end"
print("ok playing")

# lighter copies for slow TV computers
arm_row = tv.media_row("arm.mp4", 10, h264)
names = tv.rendition_names(arm_row, 1790000000)
assert sorted(names) == [480, 720, 1080] and names[720] == "arm.a6ab13b80.720p.mp4", names
assert sorted(tv.rendition_names(tv.media_row("small.mp4", 10, {"streams": [{"codec_type": "video", "codec_name": "h264",
    "width": 640, "height": 360}], "format": {"duration": "3"}}), 1)) == [480], "never above the source, but 480p always"
withr = tv.build([base | {"id": 1, "position": 0, "kind": "media", "media_name": "arm.mp4", "seconds": None}], media, [], [], day, "",
                 renditions={"arm.mp4": {720: "arm.x.720p.mp4", 480: "arm.x.480p.mp4"}})
assert withr["slides"][0]["renditions"] == {"480": "media/.tv/arm.x.480p.mp4", "720": "media/.tv/arm.x.720p.mp4"}
tv.assert_public(withr)
print("ok renditions")

# probe only new or changed files (by size and modification time); the cache is a plain dict saved as JSON
calls = []
tv.probe = lambda p: calls.append(p.name) or {"streams": [], "format": {"n": len(calls)}}
class F:  # a stand-in for a Path: name and stat()
    def __init__(self, name, size, mtime): self.name, self._s = name, type("S", (), {"st_size": size, "st_mtime": mtime})
    def stat(self): return self._s
cache = {}
first = tv.probe_cached(F("a.mp4", 10, 1.0), cache)
again = tv.probe_cached(F("a.mp4", 10, 1.0), cache)
assert calls == ["a.mp4"] and first == again, "unchanged: probed once"
tv.probe_cached(F("a.mp4", 11, 1.0), cache)
tv.probe_cached(F("a.mp4", 11, 2.0), cache)
assert calls == ["a.mp4"] * 3, "a new size or time probes again"
assert cache["a.mp4"] == {"size": 11, "mtime": 2.0, "info": {"streams": [], "format": {"n": 3}}}, cache
print("ok probe cache")

# phone pictures stored landscape with a "rotate" tag: the frame must take the shape people see
import tempfile  # noqa: E402
def jpeg(orientation, little=True):
    order = "little" if little else "big"
    entry = (0x0112).to_bytes(2, order) + (3).to_bytes(2, order) + (1).to_bytes(4, order) + orientation.to_bytes(2, order) + b"\0\0"
    tiff = (b"II*\0" if little else b"MM\0*") + (8).to_bytes(4, order) + (1).to_bytes(2, order) + entry + b"\0\0\0\0"
    app1 = b"Exif\0\0" + tiff
    return b"\xff\xd8\xff\xe1" + (len(app1) + 2).to_bytes(2, "big") + app1 + b"\xff\xd9"
tmp = Path(tempfile.mkdtemp())
for o, little in [(6, True), (8, False), (1, True)]:
    (tmp / f"o{o}.jpg").write_bytes(jpeg(o, little))
assert tv.exif_orientation(tmp / "o6.jpg") == 6 and tv.exif_orientation(tmp / "o8.jpg") == 8, "Intel and Motorola byte order"
assert tv.exif_orientation(tmp / "o1.jpg") == 1
(tmp / "plain.jpg").write_bytes(b"\xff\xd8\xff\xd9")
assert tv.exif_orientation(tmp / "plain.jpg") == 1 and tv.exif_orientation(tmp / "missing.jpg") == 1, "no EXIF, or no file: upright"
portrait_photo = {**jpg, "exif_orientation": 6}
assert (tv.media_row("me.jpg", 5, portrait_photo)["width"], tv.media_row("me.jpg", 5, portrait_photo)["height"]) == (1000, 800)
phone_video = {"streams": [{"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080,
                            "side_data_list": [{"side_data_type": "Display Matrix", "rotation": -90}]}], "format": {"duration": "9"}}
old_phone = {"streams": [{"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080, "tags": {"rotate": "270"}}],
             "format": {"duration": "9"}}
for info in (phone_video, old_phone):
    r = tv.media_row("clip.mp4", 5, info)
    assert (r["width"], r["height"]) == (1080, 1920), r
assert (tv.media_row("arm.mp4", 10, h264)["width"], tv.media_row("arm.mp4", 10, h264)["height"]) == (1920, 1080)
print("ok rotation")

# a TV page linked to a schedule event plays exactly in the event's time slot (its own dates and times are ignored)
proto = {"id": 56, "status": "approved", "starts_at": "2026-10-01T16:00:00+00:00", "ends_at": "2026-10-01T19:00:00+00:00",
         "rrule": None, "exdates": []}  # 17:00-20:00 in Lisbon
page = base | {"id": 40, "position": 0, "kind": "media", "title": "PROTO26", "media_name": "arm.mp4", "seconds": None,
               "activity_id": 56, "takeover": True, "fullscreen": True, "starts_on": "2026-01-01", "ends_on": "2026-01-02"}
reel_page = base | {"id": 41, "position": 1, "kind": "text", "title": "Normal page"}
linked = tv.link_events([page, reel_page], [proto], day)
assert (linked[0]["starts_on"], linked[0]["ends_on"], linked[0]["from_time"], linked[0]["to_time"]) == \
    ("2026-10-01", "2026-10-01", "17:00:00", "20:00:00"), linked[0]
assert linked[1] == reel_page, "pages without a link are untouched"
for clock, takeover in [("16:59", False), ("17:00", True), ("19:59", True), ("20:00", False)]:
    t = tv.build(linked, media, [], [], day, "", clock)
    assert t["takeover"] is takeover, (clock, t["playing"])
    if takeover:
        assert t["playing"] == "Takeover: PROTO26 until 20:00", t["playing"]
assert tv.build(linked, media, [], [], day, "")["slides"][0]["src"] == "media/arm.mp4", "the linked media is what plays"
assert tv.link_events([page], [proto | {"status": "cancelled"}], day)[0]["active"] is False, "a cancelled event: the page stops"
assert tv.link_events([page], [], day)[0]["active"] is False, "a deleted event: the page stops"
assert tv.link_events([page], [proto], date(2026, 10, 2))[0]["active"] is False, "another day: not playing"
weekly = proto | {"starts_at": "2026-09-17T16:00:00+00:00", "ends_at": "2026-09-17T19:00:00+00:00", "rrule": "FREQ=WEEKLY;COUNT=5"}
assert tv.link_events([page], [weekly], day)[0]["from_time"] == "17:00:00", "a weekly event: today's occurrence"
print("ok event link")
