"""Run: uv run python tests/test_usage_export.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import usage_export as u  # noqa: E402

text = u.to_csv([{"name": "Arduino, Uno", "peak": 4, "owned": None, "extra": "x"}], ("name", "peak", "owned"))
assert text == 'name,peak,owned\n"Arduino, Uno",4,\n', text
assert all(len(cols) == len(set(cols)) for cols in u.VIEWS.values())
print("ok")
