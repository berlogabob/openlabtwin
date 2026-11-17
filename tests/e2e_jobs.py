"""Browser E2E test and effort measurement for storage jobs; see docs/OPERATIONS.md.

Run against an E2E-built office with the service key and Chrome. Creates and removes
throwaway rows on the live project; not for CI.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

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


def tap(locator):
    global taps
    taps += 1
    locator.click()


def pick(pg, text):
    """Choose an entry of an open Flutter picker."""
    tap(pg.get_by_role("menuitem", name=text).or_(pg.get_by_role("button", name=text)).last)


def type_in(pg, locator, value):
    tap(locator); pg.wait_for_timeout(400)
    pg.keyboard.press("Meta+A"); pg.keyboard.type(value, delay=60); pg.wait_for_timeout(400)


checks, measurements = {}, []
taps = 0
places, items, people = [], [], []
back = "return=representation"
try:
    r15 = rows("places?select=id&code=eq.R15")[0]["id"]
    places = api("POST", "/rest/v1/places", [
        {"name": "E2E shelf 1", "kind": "storage", "tier": "fast", "code": "E2E-J1", "parent_id": r15},
        {"name": "E2E shelf 2", "kind": "storage", "tier": "fast", "code": "E2E-J2", "parent_id": r15}], back)
    s1, s2 = (p["id"] for p in places)
    items = api("POST", "/rest/v1/items", [
        {"name": "E2E Headset", "kind": "portable"}, {"name": "E2E Cable", "kind": "portable"}], back)
    headset, cable = (i["id"] for i in items)
    asset = api("POST", "/rest/v1/assets", {"item_id": headset, "serial": "E2E-JOBS-SN"}, back)[0]
    people = api("POST", "/rest/v1/people", [
        {"name": "E2E Borrower", "kind": "student"}, {"name": "E2E Other", "kind": "student"}], back)
    borrower, other = (p["id"] for p in people)
    api("POST", "/rest/v1/movements", [
        {"kind": "receive", "item_id": headset, "qty": 1, "to_place": s1, "asset_id": asset["id"]},
        {"kind": "receive", "item_id": cable, "qty": 8, "to_place": s1, "asset_id": None}])
    link = api("POST", "/auth/v1/admin/generate_link", {"type": "magiclink", "email": EMAIL, "redirect_to": BASE})
    with sync_playwright() as p:
        br = p.chromium.launch(channel="chrome", headless=True)
        pg = br.new_page(viewport={"width": 1100, "height": 1500})
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(link.get("action_link") or link["properties"]["action_link"])
        pg.get_by_role("tab", name="Storage").wait_for(timeout=30000)

        taps = 0; start = time.monotonic()
        tap(pg.get_by_role("tab", name="Storage"))
        type_in(pg, pg.get_by_role("textbox", name="Find an item, tag, place or person"), asset["tag"])
        tap(pg.get_by_role("button", name=asset["tag"]).last)  # the result tile is one button named "<tag> <serial> · <item>"
        pg.get_by_text("E2E shelf 1", exact=False).first.wait_for(timeout=30000)
        measurements.append({"job": "Find", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        checks["find shows the asset's place"] = True

        taps = 0; start = time.monotonic()
        tap(pg.get_by_role("button", name="Hand out"))
        type_in(pg, pg.get_by_role("textbox", name="Person"), "E2E Borrower")
        pick(pg, "E2E Borrower"); pg.wait_for_timeout(400)
        tap(pg.get_by_role("button", name="Confirm"))
        pg.get_by_role("button", name="Take back").wait_for(timeout=30000)
        measurements.append({"job": "Hand out", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        issues = rows(f"movements?select=person_id,from_place&asset_id=eq.{asset['id']}&kind=eq.issue")
        checks["hand out records one issue"] = issues == [{"person_id": borrower, "from_place": s1}]

        taps = 0; start = time.monotonic()
        try:
            api("POST", "/rest/v1/movements", {"kind": "issue", "item_id": headset, "asset_id": asset["id"],
                "qty": 1, "from_place": s1, "person_id": other})
            rejected = False
        except urllib.error.HTTPError as e:
            rejected = 400 <= e.code < 500 and "already out with E2E Borrower" in e.read().decode()
        measurements.append({"job": "Double loan", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        checks["double loan rejected"] = rejected

        taps = 0; start = time.monotonic()
        tap(pg.get_by_role("button", name="Take back"))
        tap(pg.get_by_role("button", name="Confirm"))
        pg.get_by_role("button", name="Hand out").wait_for(timeout=30000)
        measurements.append({"job": "Take back", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        returns = rows(f"movements?select=to_place&asset_id=eq.{asset['id']}&kind=eq.return")
        checks["take back returns to the last shelf"] = returns == [{"to_place": s1}]

        taps = 0; start = time.monotonic()
        pg.goto(BASE + "?place=E2E-J1")
        pg.get_by_text("E2E-J1 · E2E shelf 1").first.wait_for(timeout=30000)
        tap(pg.locator("[aria-label^='E2E Cable']").get_by_role("button", name="Move"))
        type_in(pg, pg.get_by_role("textbox", name="To"), "E2E-J2")
        pick(pg, "E2E-J2 · E2E shelf 2"); pg.wait_for_timeout(400)
        type_in(pg, pg.get_by_role("textbox", name="Quantity"), "5")
        tap(pg.get_by_role("button", name="Confirm"))
        pg.get_by_text("Moved E2E Cable", exact=False).first.wait_for(timeout=30000)
        measurements.append({"job": "Move 5", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        stock = rows(f"stock?select=place_id,qty&item_id=eq.{cable}&place_id=in.({s1},{s2})")
        checks["move leaves 3 and 5"] = {s["place_id"]: s["qty"] for s in stock} == {s1: 3, s2: 5}

        taps = 0; start = time.monotonic()
        pg.goto(BASE + "?place=E2E-J2")
        pg.get_by_text("E2E-J2 · E2E shelf 2").first.wait_for(timeout=30000)
        tap(pg.get_by_role("button", name="Count this shelf"))
        type_in(pg, pg.get_by_role("textbox", name="Count of E2E Cable", exact=True), "4")
        tap(pg.get_by_role("button", name="Save count"))
        pg.get_by_text("Counted.", exact=False).first.wait_for(timeout=30000)
        measurements.append({"job": "Count a shelf", "taps": taps, "seconds": round(time.monotonic() - start, 2)})
        adjusts = rows(f"movements?select=qty,note&item_id=eq.{cable}&to_place=eq.{s2}&kind=eq.adjust")
        checks["count records one stocktake adjust"] = adjusts == [{"qty": -1, "note": "stocktake"}]
        checks["counted_at set"] = rows(f"places?select=counted_at&id=eq.{s2}")[0]["counted_at"] is not None
        checks["no page errors"] = not errs
        if errs:
            print("page errors:", errs)
        br.close()
finally:
    if items:
        ids = ",".join(str(i["id"]) for i in items)
        api("DELETE", f"/rest/v1/movements?item_id=in.({ids})")
        api("DELETE", f"/rest/v1/assets?item_id=in.({ids})")
        api("DELETE", f"/rest/v1/items?id=in.({ids})")
    if people:
        api("DELETE", "/rest/v1/people?id=in.(" + ",".join(str(p["id"]) for p in people) + ")")
    if places:
        api("DELETE", "/rest/v1/places?id=in.(" + ",".join(str(p["id"]) for p in places) + ")")

print("| Job | taps | seconds |\n| --- | ---: | ---: |")
for result in measurements:
    print(f"| {result['job']} | {result['taps']} | {result['seconds']:.2f} |")
if os.environ.get("E2E_JOBS_OUT"):
    with open(os.environ["E2E_JOBS_OUT"], "w") as out:
        json.dump(measurements, out, indent=2)
        out.write("\n")
for name, ok in checks.items():
    print("✓" if ok else "✗", name)
passed = len(checks) == 8 and all(checks.values())
print("E2E", "PASS" if passed else "FAIL")
sys.exit(0 if passed else 1)
