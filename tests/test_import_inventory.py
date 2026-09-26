"""Run: uv run python tests/test_import_inventory.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import import_inventory as imp  # noqa: E402

for text, code in [(15, "R15"), ("13/14/15", "LAB"), (14, "LAB"), ("Vitrine13/14", "LAB-VIT"), ("Vitrine 13/14 ", "LAB-VIT"),
                   ("13 - Caixa de Servidor Cinza", "LAB-SRV"), ("15 - 3 Direito", "R15-R-S3"), ("15- 3 Direito", "R15-R-S3"),
                   ("15 -3 Direito", "R15-R-S3"), ("15 - 2 Direito ", "R15-R-S2"), ("15- 5 Esquerdo", "R15-L-S5"),
                   ("Caixa de Arrumos Verde- 15", "R15-BOX-GREEN"), ("Caixas de Sensores PascoCar 15", "R15-BOX-SENS"),
                   ("Caixa de Arrumos carros PascoCar - 15", "R15-BOX-CARS")]:
    assert imp.place_code(text) == code, (text, imp.place_code(text))
try:
    imp.place_code("Armario 17")
    raise AssertionError("unknown places must not be guessed")
except ValueError:
    pass
assert [c for c, *_ in imp.PLACES].count("R15-L-S5") == 1 and len({c for c, *_ in imp.PLACES}) == len(imp.PLACES)

for value, n in [(4, 4), ("11 + 10", 21), ("15 (7 Azuis + 8 Vermelhos)", 15), ("4 (Pé + Armação) + 3 (Armação Soltas)", 7),
                 ("Varios (100+)", 100), ("Varias", 1), ("5 + Saco extra", 5), (None, 1)]:
    assert imp.qty(value) == n, (value, imp.qty(value))

assert imp.tags("GS 031 + GS 019 + GS 003") == ["GS-031", "GS-019", "GS-003"]
assert imp.tags(" GS - 077") == ["GS-077"]
assert imp.tags("GS 089+ 090 + 092+093+095") == ["GS-089", "GS-090", "GS-092", "GS-093", "GS-095"]
assert imp.tags("GS 180(Caixa) + GS 176") == ["GS-180", "GS-176"]
assert imp.tags("PF 136 +... + PF 145") == [f"PF-{n}" for n in range(136, 146)]
assert imp.tags("LV-01") == ["LV-01"] and imp.tags("AS - 08 (GamesStudio - 025)") == ["AS-08"]
assert imp.tags("GS 023 + outro") == ["GS-023"]
assert imp.tags("PF 158+159, PF 160+161") == ["PF-158", "PF-159", "PF-160", "PF-161"]
assert imp.tags("GS004+GS020/GS033+GS032") == ["GS-004", "GS-020", "GS-033", "GS-032"]
assert imp.tags("EPSON ELPLP67") == [] and imp.tags("ME-8971") == [] and imp.tags(None) == []

inv = imp.Inventory()
inv.line("Consola PS4 Slim", "LAB-VIT", 10)
for n in range(3):
    inv.asset("Consola PS4 Slim", "LAB-VIT", serial=f"S{n}")
inv.asset("Consola PS4 Slim", "LAB-VIT", serial="S0", note="seen twice")
assert inv.receives() == [("Consola PS4 Slim", "LAB-VIT", 7)], "assets are taken out of the counted line"
assert len(inv.assets) == 3 and inv.assets["S0"]["note"] == "seen twice", "one asset per serial"
assert imp.norm("Cabos Ethernet") == imp.norm("cabos  ethernet") == "cabos ethernet" and imp.norm("Ecrãs") == "ecras"
inv = imp.Inventory()
inv.line("Cabos ethernet", "LAB-VIT", 22)
inv.line("Cabos Ethernet", "R15-L-S2", 10)
assert {l["item"] for l in inv.lines} == {"Cabos ethernet"}, "case-only spellings are one item, the first spelling kept"

inv = imp.Inventory()
inv.line("Ecrãs Samsung", "R15", 3)
inv.asset("Ecrãs Samsung", "R15", tag="GS-031")
inv.asset("Consola PS4 Slim", "LAB-VIT", serial="15-1-2")
inv.line("Consola PS4 Slim", "LAB-VIT", 1)
sql = imp.apply_sql(inv)
assert sql.startswith("do $$ begin if exists"), "the already-imported guard runs first, inside the same transaction"
assert sql.count("insert into places") == len(imp.PLACES) and sql.count("insert into assets") == 2
assert sql.count("'receive'") == 3, "one receive per asset plus the 2 untagged screens"
assert "a.tag = 'GS-031'" in sql and "a.serial = '15-1-2'" in sql, "a TL-numbered asset is found again by its serial"
assert "insert into assets (item_id, serial," in sql, "no tag column when the database picks the TL number"
assert imp.lit("O'Neil") == "'O''Neil'" and imp.lit(None) == "null"
print("ok")
