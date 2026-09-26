"""Browser end-to-end test of smart storage, on the live project with throwaway rows (all removed at the end).

Run from the repo root, with the office built with --dart-define=E2E=true and served at 127.0.0.1:8765/openlabtwin/office/
(see docs/OPERATIONS.md → Tests):
    set -a; . ./.env; set +a; uv run --with playwright python tests/e2e_storage.py
Covers: QR link (through sign-in) -> place screen -> count with one found-here tag -> kit issue and return of a tagged unit
-> merge of a duplicate pair in Needs attention. Not in CI: it needs the service key and Chrome.
"""
import json
import os
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

from playwright.sync_api import sync_playwright

URL, KEY = os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"]
BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8765/openlabtwin/office/"
EMAIL = os.environ.get("E2E_STAFF_EMAIL", "andre.berloga@gmail.com")


def api(method, path, body=None, prefer=None):
    h = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
    if prefer:
        h["Prefer"] = prefer
    req = urllib.request.Request(URL + path, method=method, data=None if body is None else json.dumps(body).encode(), headers=h)
    with urllib.request.urlopen(req, timeout=30) as r:
        d = r.read()
        return json.loads(d) if d else None


def rows(path):
    return api("GET", "/rest/v1/" + path)


def pick(pg, text):
    """Choose a dropdown entry: Flutter shows menu items as menuitem or button in the accessibility tree."""
    pg.get_by_role("menuitem", name=text).or_(pg.get_by_role("button", name=text)).last.click()


r15 = rows("places?select=id&code=eq.R15")[0]["id"]
back = "return=representation"
s1, s2 = (p["id"] for p in api("POST", "/rest/v1/places", [
    {"name": "E2E shelf", "kind": "storage", "tier": "fast", "code": "E2E-S1", "parent_id": r15},
    {"name": "E2E other shelf", "kind": "storage", "tier": "fast", "code": "E2E-S2", "parent_id": r15}], back))
cabo, cabos, quest = (i["id"] for i in api("POST", "/rest/v1/items", [
    {"name": "E2E Cabo HDMI longo", "kind": "portable"}, {"name": "E2E Cabos HDMI longos", "kind": "portable"},
    {"name": "E2E Quest", "kind": "portable"}], back))
q1, q2 = api("POST", "/rest/v1/assets", [{"item_id": quest, "serial": "E2E-SN-1"}, {"item_id": quest, "serial": "E2E-SN-2"}], back)
person = api("POST", "/rest/v1/people", {"name": "E2E Student", "kind": "student"}, back)[0]["id"]
start = datetime.now(timezone.utc) + timedelta(days=1)
booking = api("POST", "/rest/v1/activities", {
    "title": "E2E kit booking", "layer": "booking", "kind": "equipment", "status": "requested", "requester_id": person,
    "starts_at": start.isoformat(), "ends_at": (start + timedelta(hours=1)).isoformat()}, back)[0]["id"]
api("POST", "/rest/v1/activity_items", {"activity_id": booking, "item_id": quest, "qty": 1})
api("POST", "/rest/v1/movements", [
    {"kind": "receive", "item_id": cabo, "qty": 5, "to_place": s1, "asset_id": None},
    {"kind": "receive", "item_id": cabos, "qty": 2, "to_place": s1, "asset_id": None},
    {"kind": "receive", "item_id": quest, "qty": 1, "to_place": s1, "asset_id": q1["id"]},
    {"kind": "receive", "item_id": quest, "qty": 1, "to_place": s2, "asset_id": q2["id"]}])  # recorded on the wrong shelf
link = api("POST", "/auth/v1/admin/generate_link", {"type": "magiclink", "email": EMAIL, "redirect_to": BASE + "?place=E2E-S1"})
checks = {}
try:
    with sync_playwright() as p:
        br = p.chromium.launch(channel="chrome", headless=True)
        pg = br.new_page(viewport={"width": 1100, "height": 1500})
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))

        # 1. the QR link, through sign-in, opens the place
        pg.goto(link.get("action_link") or link["properties"]["action_link"])
        pg.get_by_text("E2E-S1 · E2E shelf").first.wait_for(timeout=30000)
        checks["QR link opens the place"] = True

        # 2. count: 4 of the 5 cables, tick the Quest listed here, and the other Quest found here
        pg.get_by_role("button", name="Count").click()
        target = pg.get_by_role("textbox", name="Count of E2E Cabo HDMI longo", exact=True)
        target.click(); pg.wait_for_timeout(400)
        pg.keyboard.press("Meta+A"); pg.keyboard.type("4", delay=60); pg.wait_for_timeout(300)
        box = pg.get_by_role("textbox", name="Found a tagged item that is not listed? Its tag or serial")
        box.click(); pg.wait_for_timeout(400)
        pg.keyboard.type(q2["tag"], delay=60); pg.wait_for_timeout(300)
        pg.get_by_role("button", name="Found here").click()
        pg.get_by_text("recorded as here (move)", exact=False).first.wait_for(timeout=20000)
        pg.wait_for_timeout(1500)
        found_box = pg.get_by_role("checkbox", name=q2["tag"] + " · E2E Quest", exact=False)
        checks["found-here tag is ticked"] = found_box.get_attribute("aria-checked") == "true"
        pg.get_by_role("checkbox", name=q1["tag"] + " · E2E Quest", exact=False).click(); pg.wait_for_timeout(300)
        pg.get_by_role("button", name="Save count").click()
        pg.get_by_text("Counted.", exact=False).first.wait_for(timeout=20000)
        pg.wait_for_timeout(1500)
        adjusts = rows(f"movements?select=qty,note,item_id&to_place=eq.{s1}&kind=eq.adjust")
        moved = rows(f"movements?select=from_place,to_place,note&asset_id=eq.{q2['id']}&kind=eq.move")
        seen = {a["id"]: a for a in rows(f"assets?select=id,condition,seen_at&item_id=eq.{quest}")}
        checks["count wrote one stocktake adjust"] = adjusts == [{"qty": -1, "note": "stocktake", "item_id": cabo}]
        checks["found-here tag moved from the other shelf"] = moved == [{"from_place": s2, "to_place": s1, "note": "stocktake"}]
        checks["both Quests seen and ok"] = all(a["condition"] == "ok" and a["seen_at"] for a in seen.values())
        checks["counted_at set"] = rows(f"places?select=counted_at&id=eq.{s1}")[0]["counted_at"] is not None

        # 3. kit issue from this shelf takes a tagged Quest; the return brings it back
        pg.get_by_role("button", name="Office").click()
        pg.get_by_text("Lab bookings").first.wait_for(timeout=30000)
        pg.locator("[aria-label^='E2E kit booking']").first.click()
        for kind, done in (("Issue kit", "Issued"), ("Return kit", "Returned")):
            print("step:", kind, flush=True)
            pg.get_by_role("button", name=kind).wait_for(timeout=20000)
            pg.get_by_role("button", name=kind).click()
            pg.wait_for_timeout(1500)
            pg.get_by_role("button", name="R15 · Room 15 (gabinete)").last.click()  # the default place is Room 15
            pg.wait_for_timeout(500)
            pick(pg, "E2E-S1 · E2E shelf")
            pg.wait_for_timeout(400)
            pg.get_by_role("button", name=kind.split()[0], exact=True).click()
            pg.get_by_text("These tagged units", exact=False).first.wait_for(timeout=20000)
            pg.get_by_role("button", name="OK").click()
            pg.get_by_text(done, exact=False).first.wait_for(timeout=20000)
            pg.wait_for_timeout(1200)
        kit = rows(f"movements?select=kind,asset_id,person_id&activity_id=eq.{booking}&order=id")
        checks["kit issue and return moved one tagged Quest"] = (
            [m["kind"] for m in kit] == ["issue", "return"] and kit[0]["asset_id"] in (q1["id"], q2["id"])
            and kit[0]["asset_id"] == kit[1]["asset_id"] and kit[0]["person_id"] == person)

        # 4. merge the duplicate pair from Needs attention
        pg.go_back()
        pg.get_by_role("button", name="Inventory").click()
        pg.get_by_text("Needs attention", exact=False).first.wait_for(timeout=20000)
        pg.get_by_role("button", name="Merge").first.click()
        pg.get_by_text("E2E Cabos HDMI longos", exact=True).last.click()
        pg.get_by_text("Merged into", exact=False).first.wait_for(timeout=20000)
        stock = rows(f"stock?select=item_id,qty&place_id=eq.{s1}&qty=neq.0&order=item_id")
        checks["merge folded 4 + 2 into 6"] = {"item_id": cabos, "qty": 6} in stock
        checks["no page errors"] = not errs
        if errs:
            print("page errors:", errs)
        br.close()
finally:
    ids = ",".join(map(str, (cabo, cabos, quest)))
    api("DELETE", f"/rest/v1/movements?item_id=in.({ids})")
    api("DELETE", f"/rest/v1/activity_items?activity_id=eq.{booking}")
    api("DELETE", f"/rest/v1/activities?id=eq.{booking}")
    api("DELETE", f"/rest/v1/people?id=eq.{person}")
    api("DELETE", f"/rest/v1/assets?item_id=in.({ids})")
    api("PATCH", f"/rest/v1/items?id=in.({ids})", {"merged_into": None})
    api("DELETE", f"/rest/v1/items?id=in.({ids})")
    api("DELETE", f"/rest/v1/places?id=in.({s1},{s2})")
    left = rows("items?select=id&name=like.E2E*") + rows("places?select=id&code=like.E2E*") + rows("people?select=id&name=like.E2E*")
    print("cleaned up" if not left else f"LEFT OVER: {left}")
for name, ok in checks.items():
    print("✓" if ok else "✗", name)
print("E2E", "PASS" if checks and all(checks.values()) and len(checks) == 9 else "FAIL")
sys.exit(0 if checks and all(checks.values()) and len(checks) == 9 else 1)
