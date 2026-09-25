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
assert not before["takeover"] and "Moda show" not in [s["title"] for s in before["slides"]], "not yet"
during = tv.build(slides + [moda], media, events, ideas, day, "17:05")
assert during["playing"] == "Takeover: Moda show until 20:00" and before["playing"].startswith("Normal loop")
assert during["takeover"] and during["slides"] == [{"kind": "text", "title": "Moda show", "body": "", "seconds": 10, "full": True}], during
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
