"""Run: uv run python tests/test_db.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import db  # noqa: E402

rows = [{"id": i} for i in range(2500)]


def pages(data):
    """Mimics PostgREST: rows start..end, capped at 1000 per request like the real API."""
    return lambda a, b: data[a:min(b, a + 999) + 1]


assert db.fetch_all(pages(rows)) == rows, "must page past the 1000-row cap"
assert db.fetch_all(pages(rows[:1000])) == rows[:1000], "exact page boundary"
assert db.fetch_all(pages([])) == []
assert db.chunks(range(5), 2) == [[0, 1], [2, 3], [4]]
assert db.chunks([], 2) == []
print("ok")
