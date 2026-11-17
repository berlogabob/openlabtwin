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
        [
            {"id": 1, "kind": "issue", "asset_id": 10, "at": "2026-11-17T00:00:00Z", "note": "tylog:t1:TL-1:out"},
            {"id": 2, "kind": "return", "asset_id": 10, "at": "2026-11-17T04:00:00Z", "note": "tylog:t1:TL-1:return"},
            {"id": 3, "kind": "issue", "asset_id": 20, "at": "2026-11-17T00:00:00Z", "note": "office loan"},
            {"id": 4, "kind": "return", "asset_id": 20, "at": "2026-11-17T08:00:00Z", "note": "office return"},
            {"id": 5, "kind": "issue", "asset_id": 30, "at": "2026-11-17T01:00:00Z", "note": "tylog:t2:TL-3:out"},
            {"id": 6, "kind": "adjust", "asset_id": None, "at": "2026-11-17T02:00:00Z", "note": "stocktake"},
            {"id": 7, "kind": "receive", "asset_id": None, "at": "2026-11-17T03:00:00Z", "note": "office correction"},
        ],
        [{"qty": 2}, {"qty": 1}],
        [{"code": "never_counted"}, {"code": "asset_broken"}, {"code": "asset_broken"}],
        now,
    )
    assert result == {
        "at": "2026-11-17T12:30:00Z",
        "places": {"total": 2, "counted": 1, "never_counted": 1},
        "items": {"total": 1, "merged": 1},
        "assets": {"total": 3, "by_condition": {"broken": 1, "ok": 2}},
        "movements": {"total": 7, "by_kind": {"adjust": 1, "issue": 3, "receive": 1, "return": 2},
                       "by_source": {"office loan": 1, "office return": 1, "office correction": 1,
                                     "stocktake": 1, "tylog": 3},
                       "by_channel": {"office": 4, "tylog": 3}},
        "loans": {"returned": 2, "median_hours": 6.0, "open_tagged": 1},
        "open_loans": {"rows": 2, "qty": 3},
        "issues": {"asset_broken": 2, "never_counted": 1},
    }


def test_channels_never_carry_note_text():
    rows = [{"id": i, "kind": "receive", "asset_id": None, "at": "2026-11-17T00:00:00Z", "note": note}
            for i, note in enumerate(["import: pairing CSV", "class of 10:30", None])]
    result = summarize([], [], [], rows, [], [], datetime(2026, 11, 17, tzinfo=timezone.utc))
    assert result["movements"]["by_channel"] == {"import": 1, "office": 2}
