"""Run: uv run python tests/test_db.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import db  # noqa: E402


class FakeQuery:
    """Mimics a PostgREST builder: .range(a, b) then .execute().data, capped at 1000 rows like the real API."""

    def __init__(self, rows):
        self.rows, self.window = rows, None

    def range(self, a, b):
        self.window = (a, min(b, a + 999))
        return self

    def execute(self):
        a, b = self.window
        return type("Result", (), {"data": self.rows[a:b + 1]})()


rows = [{"id": i} for i in range(2500)]
assert db.fetch_all(lambda: FakeQuery(rows)) == rows, "must page past the 1000-row cap"
assert db.fetch_all(lambda: FakeQuery(rows[:1000])) == rows[:1000], "exact page boundary"
assert db.fetch_all(lambda: FakeQuery([])) == []
assert db.chunks(range(5), 2) == [[0, 1], [2, 3], [4]]
assert db.chunks([], 2) == []
print("ok")
