"""Run: uv run python tests/test_import_pairing.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import import_pairing  # noqa: E402


assert import_pairing.console_key("prefix 15274525959784902 suffix") == ("27452595", "9784902")
assert import_pairing.console_key("15-27452595-9784902") == ("27452595", "9784902")
assert import_pairing.console_key("15 27452595 9784902") == ("27452595", "9784902")
assert import_pairing.pretty_serial("15 27452595 9784902") == "15-27452595-9784902"
csv_text = (
    "status,box_serial,console_serial\r\n"
    "ok,S019784862U,15274525959784902\r\n"
    "ok,S019784864U,15-27452595-9784904\r\n"
    "move,S019784899U,15-27452595-9784886\r\n"
    "no_box,,03-27452573-6951476\r\n"
    "empty_box,S019784865U,\r\n"
    "ok,S019784862U,15 27452595 9784902\r\n"
    "ok,,garbage\r\n"
)
bad = []
rows = import_pairing.read_rows(csv_text, bad)
assert bad == ["garbage"]
existing = [{"tag": "TL-0001", "serial": "15 27452595 9784902"}]
new, present = import_pairing.plan(rows, existing)
assert present == [{"serial": "15-27452595-9784902", "key": ("27452595", "9784902"),
                    "box": "S019784862U", "status": "ok", "tag": "TL-0001"}]
assert new == [
    {"serial": "15-27452595-9784904", "key": ("27452595", "9784904"), "box": "S019784864U", "status": "ok"},
    {"serial": "15-27452595-9784886", "key": ("27452595", "9784886"), "box": "S019784899U", "status": "move"},
    {"serial": "03-27452573-6951476", "key": ("27452573", "6951476"), "box": "", "status": "no_box"},
]
assert import_pairing.box_note(new[1]) == "box serial: S019784899U; moves into box S019784899U"
assert import_pairing.box_note(new[2]) == "box serial: ; no box"
sql = import_pairing.apply_sql(new, "LAB-VIT", "Consola PS4 Slim")
assert sql.count("insert into assets") == len(new)
assert sql.count("insert into movements") == len(new)
assert "do $$" in sql
assert "delete" not in sql.lower() and "update" not in sql.lower()
escaped = import_pairing.apply_sql([{"serial": "15-27452595-9784904", "box": "box's", "status": "ok"}],
                                   "LAB-VIT", "Consola PS4 Slim")
assert "box serial: box''s" in escaped
print("ok")
