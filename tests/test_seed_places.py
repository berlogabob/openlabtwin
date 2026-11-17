"""Run: uv run --with pyyaml python tests/test_seed_places.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import seed_places  # noqa: E402

tiny = {"places": [], "cabinets": [{"code": "CAB", "name": "Cabinet", "parent": "R15",
        "doors": ["L", "R"], "shelves": 2}]}
expanded = seed_places.expand(tiny)
assert [(p["code"], p["name"], p["parent"]) for p in expanded] == [
    ("CAB", "Cabinet", "R15"), ("CAB-L", "Cabinet, left door", "CAB"),
    ("CAB-L-S1", "Cabinet, left door, shelf 1", "CAB-L"),
    ("CAB-L-S2", "Cabinet, left door, shelf 2", "CAB-L"),
    ("CAB-R", "Cabinet, right door", "CAB"),
    ("CAB-R-S1", "Cabinet, right door, shelf 1", "CAB-R"),
    ("CAB-R-S2", "Cabinet, right door, shelf 2", "CAB-R")]

plan = seed_places.validate(seed_places.expand(seed_places.load_plan(Path(__file__).parent.parent / "docs/places.yaml")))
codes, names = [p["code"] for p in plan], [p["name"] for p in plan]
assert len(codes) == len(set(codes)) and len(names) == len(set(names))
assert all(seed_places.CODE.fullmatch(code) for code in codes)
assert "ARM1-L-S1" in codes and "SOLDA-D-R-S3" in codes
cabinet_codes = {f"ARM{i}" for i in range(1, 5)} | {f"SOLDA-{c}" for c in "ABCD"}
assert sum(1 for p in plan if p["code"] in cabinet_codes) == 8
assert {"STORE2", "B2-UNMAPPED"} <= set(codes)
known = {p["code"] for p in plan} | {p["code"] for p in seed_places.KNOWN_EXISTING}
assert all(p["parent"] is None or p["parent"] in known for p in plan)
new, same, conflicts = seed_places.diff(plan, seed_places.KNOWN_EXISTING)
assert not same and not conflicts and len(new) == len(plan)

arm = next(p for p in plan if p["code"] == "ARM1")
same_existing = seed_places.KNOWN_EXISTING + [{"code": "ARM1", "name": arm["name"], "parent_code": arm["parent"]}]
assert seed_places.diff(plan, same_existing)[1] == [arm]
bad_existing = seed_places.KNOWN_EXISTING + [{"code": "ARM1", "name": "Different", "parent_code": arm["parent"]}]
bad = seed_places.diff(plan, bad_existing)
assert bad[2] and bad[2][0][0]["code"] == "ARM1"
assert not seed_places.can_apply(bad[2]), "apply path must refuse whenever diff reports conflicts"
assert seed_places.can_apply(conflicts)

sql = seed_places.apply_sql(new)
assert "on conflict (code) do nothing" in sql and "delete" not in sql.lower() and "update" not in sql.lower()
assert sql.index("'ARM1'") < sql.index("'ARM1-L'") < sql.index("'ARM1-L-S1'")
print("ok")
