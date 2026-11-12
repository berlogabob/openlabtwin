"""Plan and seed storage places without changing existing places.

Usage: uv run --with pyyaml python scripts/seed_places.py [PLAN]          dry run
       uv run --with pyyaml python scripts/seed_places.py [PLAN] --sql    prints one transaction
       uv run --with pyyaml python scripts/seed_places.py [PLAN] --apply  runs it; refuses conflicts
       --offline uses the known existing places instead of querying Supabase.
"""
import re
import sys
from pathlib import Path

CODE = re.compile(r"^[A-Z0-9]+(-[A-Z0-9]+)*$")
KNOWN_EXISTING = [
    {"code": "LAB", "name": "Tech Lab", "parent_code": None},
    {"code": "R15", "name": "Room 15", "parent_code": None},
    {"code": "B2", "name": "-2 floor", "parent_code": None},
]

try:
    from import_inventory import PLACES
except ImportError:
    PLACES = []

KNOWN_EXISTING += [{"code": code, "name": name, "parent_code": parent}
                   for code, name, tier, parent in PLACES]


def load_plan(path):
    import yaml
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def expand(doc):
    out = [dict(p) for p in doc.get("places", [])]
    for cabinet in doc.get("cabinets", []):
        code, name = cabinet["code"], cabinet["name"]
        tier = cabinet.get("tier", "fast")
        out.append({"code": code, "name": name, "kind": "storage", "tier": tier, "parent": cabinet.get("parent")})
        for door in cabinet.get("doors", []):
            side = {"L": "left", "R": "right"}.get(door, door.lower())
            door_code = f"{code}-{door}"
            out.append({"code": door_code, "name": f"{name}, {side} door", "kind": "storage", "tier": tier, "parent": code})
            for n in range(1, cabinet.get("shelves", 0) + 1):
                out.append({"code": f"{door_code}-S{n}", "name": f"{name}, {side} door, shelf {n}",
                            "kind": "storage", "tier": tier, "parent": door_code})
    return out


def validate(plan, existing=KNOWN_EXISTING):
    codes, names = set(), set()
    known = {p["code"] for p in existing}
    for p in plan:
        assert CODE.fullmatch(p["code"]), f"invalid code: {p['code']}"
        assert p["code"] not in codes, f"duplicate code: {p['code']}"
        assert p["name"] not in names, f"duplicate name: {p['name']}"
        assert p["kind"] in {"room", "storage"}
        assert p["tier"] in {"fast", "long", None}
        codes.add(p["code"])
        names.add(p["name"])
        if p["parent"] is not None:
            assert p["parent"] in known or p["parent"] in codes, f"unknown parent: {p['parent']}"
    return plan


def diff(plan, existing):
    by_code = {p["code"]: p for p in existing}
    by_name = {p["name"]: p for p in existing}
    to_create, already_same, conflicts = [], [], []
    for p in plan:
        old = by_code.get(p["code"])
        same_name = by_name.get(p["name"])
        parent = p["parent"]
        if old:
            if old["name"] == p["name"] and old.get("parent_code") == parent:
                already_same.append(p)
            else:
                conflicts.append((p, old))
        elif same_name and same_name["code"] != p["code"]:
            conflicts.append((p, same_name))
        else:
            to_create.append(p)
    return to_create, already_same, conflicts


def can_apply(conflicts):
    return not conflicts


def fetch_existing():
    try:
        import db
        conn = db.connect()
        rows = db.select(conn, "places", {"select": "code,name,parent:parent_id(code)", "order": "code"})
        return [{"code": p["code"], "name": p["name"],
                 "parent_code": (p.get("parent") or {}).get("code")} for p in rows]
    except Exception as exc:
        print(f"Could not fetch places ({exc}); using KNOWN_EXISTING offline fallback.", file=sys.stderr)
        return KNOWN_EXISTING


def lit(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def apply_sql(to_create):
    return "\n".join(
        f"insert into places (code,name,kind,tier,parent_id) select {lit(p['code'])},{lit(p['name'])},"
        f"{lit(p['kind'])},{lit(p['tier'])},(select id from places where code={lit(p['parent'])}) "
        "on conflict (code) do nothing;" for p in to_create)


def report(existing, proposed, conflicts):
    print(f"{'existing places':<55} proposed (new)")
    for i in range(max(len(existing), len(proposed))):
        left = f"{existing[i]['code']}  {existing[i]['name']}" if i < len(existing) else ""
        right = f"{proposed[i]['code']}  {proposed[i]['name']}" if i < len(proposed) else ""
        print(f"{left:<55} {right}")
    if conflicts:
        print("\nConflicts:")
        for new, old in conflicts:
            print(f"  {new['code']} {new['name']} conflicts with {old['code']} {old['name']}")


def main():
    args = sys.argv[1:]
    path = next((a for a in args if not a.startswith("--")), "docs/places.yaml")
    plan = validate(expand(load_plan(path)))
    existing = KNOWN_EXISTING if "--offline" in args else fetch_existing()
    create, same, conflicts = diff(plan, existing)
    report(existing, create, conflicts)
    if "--sql" in args:
        print(apply_sql(create))
    if "--apply" in args:
        if not can_apply(conflicts):
            sys.exit("Refusing to apply while conflicts exist.")
        import sqltest
        rows, err = sqltest.query(apply_sql(create))
        if err:
            sys.exit(f"Nothing written: {err}")
        print("New codes to label: " + ", ".join(p["code"] for p in create))


if __name__ == "__main__":
    main()
