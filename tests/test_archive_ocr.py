"""Run: uv run python tests/test_archive_ocr.py"""
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
import archive_ocr as a  # noqa: E402
from PIL import Image  # noqa: E402

assert a.iso_day("2019-03-01") == "2019-03-01" and a.iso_day("1/3/2019") == "2019-03-01", "day/month/year, as on the sheets"
assert a.iso_day("01.03.19") == "2019-03-01" and a.iso_day("31/02/2019") is None and a.iso_day(None) is None

f = a.parse_fields('```json\n{"out_on": "12/03/2019", "back_on": null, "name": "Ana Silva", "student_number": "20190001",'
                   ' "course": "", "lines": [{"text": "Arduino UNO", "qty": "2"}, {"text": "cabos", "qty": "x"}, {"text": " "}],'
                   ' "notes": "null", "confidence": {"name": 0.9, "dates": "high"}}\n```')
assert f["out_on"] == "2019-03-12" and f["back_on"] is None and f["name"] == "Ana Silva" and f["course"] is None
assert f["lines"] == [{"text": "Arduino UNO", "qty": 2}, {"text": "cabos", "qty": 1}], "bad quantities become 1, empty lines go"
assert f["notes"] is None and f["confidence"] == {"name": 0.9}
try:
    a.parse_fields("I cannot read this sheet.")
    raise AssertionError("a reply without JSON must fail, so the sheet is retried")
except ValueError:
    pass

# a photo taken sideways (EXIF orientation 6) comes out upright and at most 2000 px
img = Image.new("RGB", (4000, 3000), "white")
exif = img.getexif()
exif[0x0112] = 6
buf = io.BytesIO()
img.save(buf, "JPEG", exif=exif)
tmp = Path(__file__).parent / "_sideways.jpg"
tmp.write_bytes(buf.getvalue())
try:
    jpeg, taken = a.prepare(tmp)
    with Image.open(io.BytesIO(jpeg)) as out:
        assert out.size == (1500, 2000), out.size
    assert taken is None
finally:
    tmp.unlink()

m = a.vision_messages("read", b"\xff\xd8")
assert m[0]["content"][0]["image_url"]["url"].startswith("data:image/jpeg;base64,") and m[0]["content"][1]["text"] == "read"
print("ok")
