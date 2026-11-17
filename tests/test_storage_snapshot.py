"""Run: uv run pytest tests/test_storage_snapshot.py -q"""
from datetime import datetime, timezone
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from storage_snapshot import summarize  # noqa: E402


def test_summarize_storage_rows():
    now = datetime(2026, 11, 17, 12, 30, tzinfo=timezone.utc)
    result = summarize(
        [{"counted_at": "2026-11-01T10:00:00Z"}, {"counted_at": None}],
        [{"merged_into": None}, {"merged_into": 1}],
        [{"condition": "ok"}, {"condition": "broken"}, {"condition": "ok"}],
        [{"kind": "receive", "note": None}, {"kind": "issue", "note": "tylog:abc:out"},
         {"kind": "receive", "note": "import: Inventario Tech Lab.xlsx"}],
        [{"qty": 2}, {"qty": 1}],
        [{"code": "never_counted"}, {"code": "asset_broken"}, {"code": "asset_broken"}],
        now,
    )
    assert result == {
        "at": "2026-11-17T12:30:00Z",
        "places": {"total": 2, "counted": 1, "never_counted": 1},
        "items": {"total": 1, "merged": 1},
        "assets": {"total": 3, "by_condition": {"broken": 1, "ok": 2}},
        "movements": {"total": 3, "by_kind": {"issue": 1, "receive": 2},
                       "by_source": {"import": 1, "none": 1, "tylog": 1}},
        "open_loans": {"rows": 2, "qty": 3},
        "issues": {"asset_broken": 2, "never_counted": 1},
    }
