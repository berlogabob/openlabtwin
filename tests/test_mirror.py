"""Run: uv run python tests/test_mirror.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import mirror  # noqa: E402

assert mirror.column_type("id", [1, 2]) == "bigint"
assert mirror.column_type("qty", [1, 2.5]) == "numeric"
assert mirror.column_type("public", [True, False]) == "boolean"
assert mirror.column_type("counted_at", [None]) == "timestamptz" and mirror.column_type("at", ["2026-09-26T10:00:00+00:00"]) == "timestamptz"
assert mirror.column_type("place_ids", [[1, 2]]) == "jsonb" and mirror.column_type("note", [None, "x"]) == "text"
sql = mirror.table_sql("items", [{"id": 1, "name": "Cabo $j$ HDMI", "note": None}])
assert sql.startswith("drop table if exists items cascade;") and '"id" bigint, "name" text, "note" text' in sql
assert "$jj$" in sql, "the dollar quote never collides with the data"
assert mirror.table_sql("empty", []).endswith("create table empty ();")
assert '"to_place" bigint' in mirror.table_sql("movements", []), "an empty movements table still has the columns the views read"
assert '"out_on" date' in mirror.table_sql("archive_loans", []), "an empty archive_loans still has the columns usage_events reads"
assert mirror.column_type("out_on", ["2019-03-01"]) == "date" and mirror.column_type("date", [None]) == "date"
print("ok")
