"""Run: uv run python tests/test_labels.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import labels  # noqa: E402

places = [{"id": 1, "code": "R15", "name": "Room 15", "parent_id": None},
          {"id": 2, "code": "R15-L", "name": "Left", "parent_id": 1},
          {"id": 3, "code": "R15-L-S1", "name": "Shelf 1", "parent_id": 2},
          {"id": 4, "code": "B2", "name": "-2 floor", "parent_id": None},
          {"id": 5, "code": None, "name": "No code yet", "parent_id": 4}]
assert [p["code"] for p in labels.subtree(places, "R15-L")] == ["R15-L", "R15-L-S1"]
assert [p["code"] for p in labels.subtree(places, None)] == ["R15", "R15-L", "R15-L-S1", "B2"], "parents first, uncoded left out"
assert labels.place_url("R15-L-S1") == "https://berlogabob.github.io/openlabtwin/office/?place=R15-L-S1"
page = labels.label_html([("R15-L-S1", "Shelf <1>", labels.place_url("R15-L-S1"))])
assert page.count("<svg") == 1 and "R15-L-S1" in page and "Shelf &lt;1&gt;" in page and "@page" in page
print("ok")
