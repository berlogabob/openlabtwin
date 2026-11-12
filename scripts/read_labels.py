"""Read PlayStation 4 serial labels from a folder using the archive vision model.

Usage: uv run python scripts/read_labels.py FOLDER [--csv OUT]
"""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import archive_ocr  # noqa: E402

PROMPT = "This photo shows a PlayStation 4 serial number label. Reply with only the serial number printed under the barcode, format NN-NNNNNNNN-NNNNNNN."


def serial_number(reply):
    match = re.search(r"\d{2}-?\d{8}-?\d{7}", reply or "")
    if not match:
        return None
    digits = match.group().replace("-", "")
    return f"{digits[:2]}-{digits[2:10]}-{digits[10:]}"


def main():
    args = sys.argv[1:]
    folder = Path(args[0])
    out = Path(args[args.index("--csv") + 1]) if "--csv" in args else None
    photos = sorted((p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png"}), key=lambda p: p.name)
    rows = []
    for photo in photos:
        jpeg, _ = archive_ocr.prepare(photo)
        serial = serial_number(archive_ocr.ask(PROMPT, jpeg)) or "UNREAD"
        rows.append((photo.name, serial))
        print(f"{photo.name}\t{serial}")
    print()
    print("\n".join(serial for _, serial in rows))
    if out:
        with out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(("file", "serial"))
            writer.writerows(rows)


if __name__ == "__main__":
    main()
