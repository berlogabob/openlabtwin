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
(d / "data/all.json").write_text(json.dumps([lesson, lesson | {"course": "Mac lab", "rooms": [MAC], "layer": "booking"}]))
(d / "tv.json").write_text(json.dumps({"generated": "", "ideas": [{"title": "Micro robot arm", "summary": "An ESP32 arm."}],
    "slides": [{"kind": "media", "src": "media/tall.svg", "video": False, "w": 400, "h": 800, "title": "Tall photo", "body": "", "seconds": 1},
               {"kind": "text", "title": "Welcome", "body": "Open lab on Fridays", "seconds": 1}]}))
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
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 0.5) < 0.02, f"frame follows the photo's 1:2 shape: {box}"
    aside = page.locator("#schedule").bounding_box()
    assert 0.3 < aside["width"] / 1920 < 0.37, f"schedule column is a third: {aside}"
    page.wait_for_selector("#frame h1:has-text('Welcome')", timeout=4000)
    box = page.locator("#frame").bounding_box()
    assert abs(box["width"] / box["height"] - 16 / 9) < 0.02, f"text slides are 16:9: {box}"
    page.wait_for_selector("#frame h1:has-text('Micro robot arm')", timeout=4000)
    assert "updated" in page.inner_text("footer")
    if len(sys.argv) > 1:
        page.screenshot(path=sys.argv[1])
server.shutdown()
print("ok")
