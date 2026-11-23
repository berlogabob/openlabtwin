"""Run: uv run python tests/test_backup.py"""
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import backup  # noqa: E402

days = ["2026-09-03", "2026-09-01", "2026-09-02", "2026-09-04"]
assert backup.prune(days, 2) == ["2026-09-01", "2026-09-02"], "oldest go first"
assert backup.prune(days, 4) == [] and backup.prune([], 30) == []
assert backup.TABLES.index("activities") < backup.TABLES.index("activity_items") < backup.TABLES.index("audit_log")
assert backup.TABLES.index("items") < backup.TABLES.index("assets") < backup.TABLES.index("item_photos") < backup.TABLES.index("movements")
assert backup.TABLES.index("people") < backup.TABLES.index("issue_waivers") and backup.ORDER["issue_waivers"] == "key"
assert backup.TABLES.index("items") < backup.TABLES.index("archive_sheets") < backup.TABLES.index("archive_loans")
T = backup.TABLES.index
assert T("people") < T("ideas") < T("idea_skills") and T("ideas") < T("idea_matches")
assert T("activities") < T("tv_slides") and T("tv_media") < T("tv_slides")
assert backup.ORDER["idea_skills"] == "idea_id,side,phrase" and backup.ORDER["idea_matches"] == "idea_a,idea_b,kind" and backup.ORDER["tv_media"] == "name"
sql = "\n".join(p.read_text(encoding="utf-8").lower() for p in sorted((Path(__file__).parent.parent / "supabase" / "migrations").glob("*.sql")))
created = set(re.findall(r"create table (?:if not exists )?(\w+)", sql)) - set(re.findall(r"drop table (?:if exists )?(\w+)", sql))
assert created == set(backup.TABLES) | backup.SKIP, f"backup out of step with migrations: {created ^ (set(backup.TABLES) | backup.SKIP)}"
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    paths = ["items/1/a.jpg", "items/1/a.thumb.jpg", "items/2/b.jpg", "items/2/b.thumb.jpg"]
    calls = []
    def fetch(path):
        calls.append(path)
        return None if path == paths[3] else path.encode()
    assert backup.copy_photos([{"path": paths[0]}, {"path": paths[2]}], root / "photos", fetch) == (3, 1)
    for path in paths[:3]:
        assert (root / "photos" / path).read_bytes() == path.encode()
    calls.clear()
    assert backup.copy_photos([{"path": paths[0]}, {"path": paths[2]}], root / "photos", fetch) == (0, 1)
    assert calls == [paths[3]]
    for day in days:
        (root / day).mkdir()
    candidates = [p.name for p in root.iterdir() if p.is_dir() and len(p.name) == 10]
    assert "photos" not in candidates and "photos" not in backup.prune(candidates, 2)
print("ok")
