"""Browser end-to-end test of the paper loan archive, on the live project with throwaway rows (all removed at the end).

Run from the repo root, with the office built with --dart-define=E2E=true and served at 127.0.0.1:8765/openlabtwin/office/:
    set -a; . ./.env; set +a; uv run --with playwright python tests/e2e_archive.py
A sheet as the node's reader leaves it (fictional student, generated photo) -> Archive screen -> approve -> archive_loans
-> Usage screen. Not in CI: it needs the service key and Chrome.
"""
import io
import json
import os
import sys
import urllib.request

from PIL import Image, ImageDraw
from playwright.sync_api import sync_playwright

URL, KEY = os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8765/openlabtwin/office/"
EMAIL = os.environ.get("E2E_STAFF_EMAIL", "andre.berloga@gmail.com")


def api(method, path, body=None, prefer=None, raw=None, ctype="application/json"):
    h = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": ctype, **({"Prefer": prefer} if prefer else {})}
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(urllib.request.Request(URL + path, method=method, data=data, headers=h), timeout=30) as r:
        d = r.read()
        return json.loads(d) if d and r.headers.get_content_type() == "application/json" else None


img = Image.new("RGB", (800, 1000), "white")
ImageDraw.Draw(img).text((40, 40), "E2E loan sheet\nNome: E2E Aluna Ficticia\nArduino UNO | 2", fill="black")
buf = io.BytesIO()
img.save(buf, "JPEG")
item = api("POST", "/rest/v1/items", {"name": "E2E Arduino UNO", "kind": "portable"}, "return=representation")[0]["id"]
student = api("POST", "/rest/v1/people", {"name": "E2E Aluna Ficticia", "kind": "student", "student_number": "E2E-2019"},
              "return=representation")[0]["id"]
fields = {"out_on": "2019-03-12", "back_on": "2019-03-29", "name": "E2E Aluna Ficticia", "student_number": "E2E-2019",
          "course": "E2E Design", "lines": [{"text": "E2E Arduino UNO", "qty": 2}, {"text": "E2E caixa de fios", "qty": 1}], "notes": None}
sheet = api("POST", "/rest/v1/archive_sheets", {"sha256": "e2e-sheet-sha", "file_name": "e2e_sheet.jpg", "status": "extracted",
                                                  "extracted": fields, "raw_text": "E2E loan sheet"}, "return=representation")[0]["id"]
api("POST", f"/storage/v1/object/archive/{sheet}.jpg", raw=buf.getvalue(), ctype="image/jpeg")
api("PATCH", f"/rest/v1/archive_sheets?id=eq.{sheet}", {"image_path": f"{sheet}.jpg"})
link = api("POST", "/auth/v1/admin/generate_link", {"type": "magiclink", "email": EMAIL, "redirect_to": BASE})
checks = {}
try:
    with sync_playwright() as p:
        br = p.chromium.launch(channel="chrome", headless=True)
        pg = br.new_page(viewport={"width": 1300, "height": 1100})
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(link.get("action_link") or link["properties"]["action_link"])
        pg.get_by_text("Lab bookings").first.wait_for(timeout=30000)
        pg.get_by_role("button", name="Inventory").click()
        pg.get_by_role("button", name="Archive").click()
        pg.locator("[aria-label^='e2e_sheet.jpg']").or_(pg.get_by_text("e2e_sheet.jpg")).first.click()
        pg.get_by_role("button", name="Approve").wait_for(timeout=30000)
        pg.wait_for_timeout(3000)  # the item suggestions arrive
        # the student (matched by number) and the item (suggested for its line) are prefilled in pickers, whose text Flutter
        # doesn't expose to the test: approving without touching them proves both (checked in the saved loans below)
        pg.get_by_role("button", name="Approve").click()
        pg.get_by_text("Paper archive").first.wait_for(timeout=30000)  # back on the Archive list
        pg.wait_for_timeout(2000)
        loans = api("GET", f"/rest/v1/archive_loans?select=person_id,course,item_id,item_text,qty,out_on,back_on&sheet_id=eq.{sheet}&order=id")
        print(loans)
        checks["approve, untouched, saved the matched student and suggested item, and the unmatched line"] = (
            len(loans) == 2 and loans[0]["item_id"] == item and loans[0]["qty"] == 2 and loans[1]["item_id"] is None
            and all(l["person_id"] == student and l["out_on"] == "2019-03-12" and l["back_on"] == "2019-03-29" for l in loans))
        checks["the sheet is reviewed"] = api("GET", f"/rest/v1/archive_sheets?select=status&id=eq.{sheet}")[0]["status"] == "reviewed"
        pg.go_back()  # to Inventory
        pg.get_by_role("button", name="Usage").click()
        pg.wait_for_timeout(4000)
        body = pg.evaluate("[...document.querySelectorAll('flt-semantics')].map(e => e.getAttribute('aria-label') || e.innerText).join('|')")
        checks["usage shows the item"] = "E2E Arduino UNO" in body
        checks["no page errors"] = not errs
        if errs:
            print("page errors:", errs)
        br.close()
finally:
    api("DELETE", f"/rest/v1/archive_loans?sheet_id=eq.{sheet}")
    api("DELETE", f"/rest/v1/archive_sheets?id=eq.{sheet}")
    api("DELETE", "/storage/v1/object/archive", {"prefixes": [f"{sheet}.jpg"]})
    api("DELETE", f"/rest/v1/items?id=eq.{item}")
    api("DELETE", f"/rest/v1/people?id=eq.{student}")
    left = api("GET", "/rest/v1/archive_sheets?select=id&sha256=eq.e2e-sheet-sha") + api("GET", "/rest/v1/items?select=id&name=like.E2E*")
    print("cleaned up" if not left else f"LEFT OVER: {left}")
for name, ok in checks.items():
    print("✓" if ok else "✗", name)
passed = len(checks) == 4 and all(checks.values())
print("E2E", "PASS" if passed else "FAIL")
sys.exit(0 if passed else 1)
