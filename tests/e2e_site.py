"""Browser end-to-end test of the public site's forms (throwaway rows, removed at the end).

Run with the site built (jaspr build, BASE=/openlabtwin/) and served at a base URL, or against the live site:
    set -a; . ./.env; set +a; uv run --with playwright python tests/e2e_site.py http://127.0.0.1:8766/openlabtwin/
Covers the one picker (courses from the timetable, the lab's items with quantities, × to remove), the required student
number, the schedule's room chip, the idea skills and Book me's number field. Not in CI: it needs the service key and Chrome.
"""
import json, os, sys, urllib.parse, urllib.request
from playwright.sync_api import sync_playwright
URL, KEY = os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "https://berlogabob.github.io/openlabtwin/"
def api(m, p, body=None):
    r = urllib.request.Request(URL + p, method=m, data=None if body is None else json.dumps(body).encode(), headers={"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    d = urllib.request.urlopen(r, timeout=30).read(); return json.loads(d) if d else None
ok = {}
try:
    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome"); pg = b.new_page(viewport={"width": 430, "height": 1400}); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(BASE + "kit/")
        eq = pg.locator("input[list='items-list']"); eq.wait_for(timeout=30000); pg.wait_for_timeout(3000)
        ok["course list from the timetable"] = pg.locator("#course-list option").count() > 100
        ok["equipment list from the catalogue"] = pg.locator("#items-list option").count() > 100
        ok["Zortrax not offered"] = pg.locator("#items-list option[value*='Zortrax']").count() == 0
        eq.fill("Arduino Yún"); pg.wait_for_timeout(300)
        pg.locator("input[list='items-list']").fill("Cabos HDMI"); pg.wait_for_timeout(300)
        pg.get_by_label("How many Cabos HDMI").fill("3")
        first = pg.locator("#course-list option").first.get_attribute("value")
        pg.locator("input[list='course-list']").fill(first); pg.wait_for_timeout(300)
        chips = pg.locator(".chip").all_inner_texts(); print("chips:", chips)
        ok["picked items and course show as chips"] = len(chips) == 3
        pg.get_by_role("button", name="Remove Arduino Yún").click(); pg.wait_for_timeout(200)
        ok["× removes a chip"] = len(pg.locator(".chip").all_inner_texts()) == 2
        pg.get_by_label("Name", exact=True).fill("E2E Prof"); pg.get_by_label("Email").fill("e2e.kit2@example.com")
        pg.get_by_role("button", name="Send request").click(); pg.wait_for_timeout(1500)
        ok["number required before sending"] = "student number" in pg.locator("p.error").inner_text()
        pg.get_by_label("Student number (staff: your staff number)").fill("STAFF-E2E")
        pg.get_by_role("button", name="Send request").click(); pg.get_by_text("Request sent").wait_for(timeout=20000)
        rows = api("GET", "/rest/v1/activities?select=id,purpose,activity_items(qty,items(name))&kind=eq.equipment&status_token=not.is.null")
        ok["request stored with its course and 3 × Cabos HDMI"] = any(r["activity_items"] == [{"qty": 3, "items": {"name": "Cabos HDMI"}}] and first in r["purpose"] for r in rows)
        pg.goto(BASE + "?room=Lab.+e+Estudo+de+Jogos+-+Tech+Lab+(Oriente)"); pg.wait_for_timeout(5000)
        ok["schedule filters still show the room chip"] = "Tech Lab" in " ".join(pg.locator("#filters .chip").all_inner_texts())
        pg.goto(BASE + "ideas/"); pg.locator("input[list='bring-list']").wait_for(timeout=20000)
        ok["idea skills use the same picker"] = pg.locator("#bring-list option").count() > 10
        pg.goto(BASE + "book/"); pg.get_by_label("Student number (staff: your staff number)").wait_for(timeout=20000)
        ok["Book me asks for the number"] = True
        ok["no page errors"] = not errs
        b.close()
finally:
    for a in api("GET", "/rest/v1/activities?select=id,requester_id,people!activities_requester_id_fkey(email)&kind=eq.equipment&status_token=not.is.null") or []:
        if (a.get("people") or {}).get("email", "").startswith("e2e."):
            api("DELETE", f"/rest/v1/activity_items?activity_id=eq.{a['id']}"); api("DELETE", f"/rest/v1/activities?id=eq.{a['id']}")
    api("DELETE", "/rest/v1/people?email=eq.e2e.kit2@example.com")
for k, v in ok.items(): print("✓" if v else "✗", k)
passed = len(ok) == 11 and all(ok.values())
print("E2E", "PASS" if passed else "FAIL")
sys.exit(0 if passed else 1)
