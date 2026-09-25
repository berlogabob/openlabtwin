"""Browser check of apps/tv/index.html with sample data. Run: uv run --with playwright python tests/check_tv_page.py"""
import json
import shutil
import sys
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
busy = [lesson | {"start": f"{h:02}:00", "end": f"{h:02}:50", "course": f"Busy lesson {h}", "teachers": ["A Teacher"]} for h in range(8, 21)]
(d / "data/all.json").write_text(json.dumps([lesson, lesson | {"course": "Mac lab", "rooms": [MAC], "layer": "booking"}] + busy))
long = "A small robot arm built with servos and 3D-printed parts, controlled remotely from a smartphone. " * 6
(d / "tv.json").write_text(json.dumps({"generated": "2026-01-01T10:00:00+00:00", "ideas": [{"title": "Micro robot arm with a very long descriptive title", "summary": long}],
    "slides": [{"kind": "media", "src": "media/tall.svg", "video": False, "w": 400, "h": 800, "title": "Tall photo", "body": "", "seconds": 1},
               {"kind": "text", "title": "Welcome", "body": "Open lab on Fridays", "seconds": 1},
               {"kind": "ideas", "seconds": 1}]}))
from datetime import datetime, timedelta
soon = (datetime.now() + timedelta(minutes=1)).strftime("%H:%M")
normal = {"kind": "text", "title": "Normal page", "body": "", "seconds": 1}
takeover = {"generated": "", "takeover": False, "ideas": [], "slides": [normal, {"kind": "text", "title": "Moda show", "body": "Tonight 17:00",
            "seconds": 1, "full": True, "takeover": True, "from": soon, "to": "23:59"}]}
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Quiet, directory=str(d)))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}/index.html?room={LAB}&room={MAC}"

with sync_playwright() as p:
    page = p.chromium.launch(channel="chrome").new_page(viewport={"width": 1920, "height": 1080})
    page.goto(url)
    page.wait_for_selector("#frame img")
    heads = page.locator("#schedule h2").all_text_contents()
    assert heads == ["Lab. e Estudo de Jogos - Tech Lab", "Sala 017 Mac 1"], heads
    assert "VR Development" in page.inner_text("#schedule") and page.locator("#schedule article.booking.now").count() == 1
    assert page.locator("#schedule .now-line").count() == 2, "a now line in each room"
    picks = page.evaluate("""() => { const s = {src: 'o.mov', renditions: {'480': 'a', '720': 'b', '1080': 'c'}};
        const r = []; for (const t of [480, 720, 1080]) { tier = t; r.push(videoSrc(s)); } tier = 480; r.push(videoSrc({src: 'o'}));
        tier = 360; r.push(videoSrc(s)); return r; }""")
    assert picks == ["a", "b", "c", "o", "a"], f"quality tiers pick the right copy: {picks}"
    fits = page.eval_on_selector("#schedule", "a => [a.scrollHeight, a.clientHeight, a.style.fontSize]")
    assert fits[0] <= fits[1] and fits[2] != "100%", f"a busy day shrinks to fit the column: {fits}"
    assert "not updating" in page.inner_text("footer"), "an old playlist is flagged on the TV"
    edges = page.eval_on_selector_all("#schedule article", "a => a.map(e => getComputedStyle(e).borderLeftColor)")
    assert edges[0] == "rgb(179, 38, 30)" and edges[-1] == "rgb(30, 92, 179)", f"lessons red, bookings blue: {edges}"
    look = page.eval_on_selector_all("#schedule article", "a => a.map(e => [getComputedStyle(e).boxShadow, getComputedStyle(e).outlineColor, e.getBoundingClientRect().height])")
    assert all(x[0] == "none" for x in look), f"no glow: {look}"
    assert look[-1][1] == "rgb(30, 92, 179)", f"the running booking is outlined in its own blue: {look}"
    assert look[0][2] == look[1][2], "outline adds no height (running lesson vs a finished one)"
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 0.5) < 0.02, f"frame follows the photo's 1:2 shape: {box}"
    aside = page.locator("#schedule").bounding_box()
    assert 0.3 < aside["width"] / 1920 < 0.37, f"schedule column is a third: {aside}"
    page.wait_for_selector("#frame h1:has-text('Welcome')", timeout=4000)
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 16 / 9) < 0.02, f"text slides are 16:9: {box}"
    page.wait_for_selector("#frame h1:has-text('Micro robot arm')", timeout=4000)
    over = page.eval_on_selector("#frame .text", "t => [t.scrollHeight - t.clientHeight, t.scrollWidth - t.clientWidth]")
    assert over[0] <= 0 and over[1] <= 0, f"long idea text fits the frame: {over}"
    top = page.text_content("#top")
    assert "Tech Lab" in top and ":" not in top, f"top line: day and rooms, no clock: {top!r}"
    # event mode: tv.json switches to a takeover, the TV follows on its next reload, full screen
    (d / "tv.json").write_text(json.dumps(takeover))
    page.evaluate("load()")
    page.wait_for_selector("#frame h1:has-text('Normal page')", timeout=4000)
    assert page.evaluate("!live().takeover"), "before its time the takeover page stays out"
    page.evaluate(f"(() => {{ const real = Date; const t = new real(real.now() + 61000); Date = class extends real {{ constructor(...a) {{ super(...(a.length ? a : [t])); }} static now() {{ return t.getTime(); }} }}; }})()")
    page.evaluate("watch()")
    page.wait_for_selector("#frame h1:has-text('Moda show')", timeout=4000)
    assert page.evaluate("document.body.classList.contains('full')") and not page.locator("#schedule").is_visible()
    box = page.locator("#frame").bounding_box()
    assert box["width"] > 1600, f"full screen frame: {box}"
    if len(sys.argv) > 1:
        page.screenshot(path=sys.argv[1])

server.shutdown()
print("ok")
