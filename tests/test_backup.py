"""Run: uv run python tests/test_backup.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import backup  # noqa: E402

days = ["2026-09-03", "2026-09-01", "2026-09-02", "2026-09-04"]
assert backup.prune(days, 2) == ["2026-09-01", "2026-09-02"], "oldest go first"
assert backup.prune(days, 4) == [] and backup.prune([], 30) == []
assert backup.TABLES.index("activities") < backup.TABLES.index("activity_items") < backup.TABLES.index("audit_log")
print("ok")
