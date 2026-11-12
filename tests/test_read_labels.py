"""Run: uv run python tests/test_read_labels.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import read_labels  # noqa: E402

assert read_labels.serial_number("12-345678901234567") == "12-34567890-1234567"
assert read_labels.serial_number("SN: 12345678901234567") == "12-34567890-1234567"
assert read_labels.serial_number("not a serial") is None
print("ok")
