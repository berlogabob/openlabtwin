"""Paper loan archive reader (edge node, every 15 min): photos of the old A4 loan sheets -> transcription and fields.

Staff drop photos into the shared folder smb://<node>/archive (~/archive/inbox). Each new photo is turned upright, shrunk
to a 2000 px JPEG, stored privately (Supabase Storage bucket 'archive') and recorded as an archive_sheets row; the
original moves to ~/archive/originals. A vision model on Unsloth Studio then transcribes the sheet and extracts its fields.
Nothing becomes a loan until a staff member reviews the sheet in the office (Archive screen).

Usage: uv run python scripts/archive_ocr.py               take in new photos, read up to READ_LIMIT sheets
       uv run python scripts/archive_ocr.py --file PHOTO  read one photo and print what the model sees (writes nothing)
Settings (.env): AI_URL, AI_KEY (the Studio server, as for the idea AI), ARCHIVE_MODEL (a vision model),
                 ARCHIVE_DIR (default ~/archive). Nothing leaves the lab except the private copy in Supabase Storage.
"""
import base64
import hashlib
import io
import json
import os
import re
import sys
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

BASE = (os.environ.get("AI_URL") or "http://localhost:11434").rstrip("/")
KEY = os.environ.get("AI_KEY", "")
MODEL = os.environ.get("ARCHIVE_MODEL", "unsloth/gemma-4-26B-A4B-it-qat-GGUF")
ROOT = Path(os.environ.get("ARCHIVE_DIR") or Path.home() / "archive")
IMAGES = {".jpg", ".jpeg", ".png", ".heic", ".heif"}
SIDE, READ_LIMIT, RETRY_AFTER = 2000, 5, timedelta(hours=6)

PROMPT_READ = ("This is a photo of a paper equipment loan sheet from a university lab in Lisbon: what a student took home, "
               "mostly handwritten, in Portuguese. Transcribe all the text exactly as written, line by line, keeping table "
               "rows on one line each (cells separated by ' | '). Do not translate or correct anything. Write [?] for an "
               "unreadable word. Output only the transcription.")
PROMPT_FIELDS = ("From the loan sheet in the photo and its transcription below, return only this JSON: "
                 '{"out_on": "YYYY-MM-DD or null", "back_on": "YYYY-MM-DD or null", "name": "student name or null", '
                 '"student_number": "or null", "course": "or null", '
                 '"lines": [{"text": "item exactly as written", "qty": 1}], "notes": "anything else worth keeping, or null", '
                 '"confidence": {"name": 0.0, "dates": 0.0, "lines": 0.0}}. '
                 "out_on is when it was taken, back_on when it was returned. Dates on these sheets are day/month/year. "
                 "Use null for anything missing or unreadable; never guess. Transcription:\n")


def prepare(path):
    """(JPEG bytes upright and at most SIDE px, when the photo was taken or None)."""
    from PIL import Image, ImageOps
    try:
        from pillow_heif import register_heif_opener  # iPhone photos
        register_heif_opener()
    except ImportError:
        pass
    with Image.open(path) as im:
        taken = im.getexif().get_ifd(0x8769).get(36867) or im.getexif().get(306)  # DateTimeOriginal, else DateTime
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((SIDE, SIDE))
        out = io.BytesIO()
        im.save(out, "JPEG", quality=85)
    when = None
    if taken:
        try:
            when = datetime.strptime(str(taken).strip(), "%Y:%m:%d %H:%M:%S").isoformat()
        except ValueError:
            pass
    return out.getvalue(), when


def vision_messages(prompt, jpeg):
    return [{"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()}},
        {"type": "text", "text": prompt}]}]


def ask(prompt, jpeg, json_reply=False):
    """One answer from the vision model (OpenAI-compatible; thinking off, or the answer ends up in the reasoning)."""
    body = {"model": MODEL, "messages": vision_messages(prompt, jpeg), "temperature": 0, "max_tokens": 3000,
            "chat_template_kwargs": {"enable_thinking": False}, **({"response_format": {"type": "json_object"}} if json_reply else {})}
    headers = {"Content-Type": "application/json", **({"Authorization": f"Bearer {KEY}"} if KEY else {})}
    req = urllib.request.Request(BASE + "/v1/chat/completions", data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=900) as r:
        return (json.load(r)["choices"][0]["message"]["content"] or "").strip()


def iso_day(v):
    """A date from the model as YYYY-MM-DD, accepting day/month/year; None if it isn't a real date."""
    s = str(v or "").strip()
    for pattern, order in ((r"(\d{4})-(\d{1,2})-(\d{1,2})", "ymd"), (r"(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})", "dmy")):
        m = re.fullmatch(pattern, s)
        if m:
            a, b, c = (int(x) for x in m.groups())
            y, mo, d = (a, b, c) if order == "ymd" else (c + 2000 if c < 100 else c, b, a)
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                return None
    return None


def parse_fields(raw):
    """The model's JSON as clean fields; raises ValueError when there is no usable object."""
    m = re.search(r"\{.*\}", raw or "", re.S)
    if not m:
        raise ValueError("no JSON in the reply")
    data = json.loads(m.group(0))
    text = lambda k: (str(data.get(k)).strip() or None) if data.get(k) not in (None, "", "null") else None  # noqa: E731
    lines = []
    for line in data.get("lines") or []:
        t = str((line or {}).get("text") or "").strip() if isinstance(line, dict) else str(line).strip()
        if not t:
            continue
        try:
            qty = max(1, int(float((line or {}).get("qty") or 1))) if isinstance(line, dict) else 1
        except (TypeError, ValueError):
            qty = 1
        lines.append({"text": t, "qty": qty})
    conf = data.get("confidence") if isinstance(data.get("confidence"), dict) else {}
    return {"out_on": iso_day(data.get("out_on")), "back_on": iso_day(data.get("back_on")), "name": text("name"),
            "student_number": text("student_number"), "course": text("course"), "lines": lines, "notes": text("notes"),
            "confidence": {k: v for k, v in conf.items() if isinstance(v, (int, float))}}


def read_sheet(jpeg):
    """(transcription, fields) for one prepared photo."""
    raw_text = ask(PROMPT_READ, jpeg)
    return raw_text, parse_fields(ask(PROMPT_FIELDS + raw_text, jpeg, json_reply=True))


def upload(db, path, jpeg):
    base, key = db
    req = urllib.request.Request(base.replace("/rest/v1", "/storage/v1") + f"/object/archive/{path}", data=jpeg, method="POST",
                                 headers={"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "image/jpeg", "x-upsert": "true"})
    urllib.request.urlopen(req, timeout=120).read()


def take_in(db):
    """New photos in the inbox become archive_sheets rows (status new), their copy stored, the original moved."""
    from db import request, select
    inbox, originals, copies = ROOT / "inbox", ROOT / "originals", ROOT / "copies"
    for d in (inbox, originals, copies):
        d.mkdir(parents=True, exist_ok=True)
    known = {r["sha256"] for r in select(db, "archive_sheets", {"select": "sha256", "order": "id"})}
    for f in sorted(inbox.iterdir()):
        if f.suffix.lower() not in IMAGES or f.name.startswith("."):
            continue
        sha = hashlib.sha256(f.read_bytes()).hexdigest()
        if sha not in known:
            jpeg, taken = prepare(f)
            row = request(db, "POST", "archive_sheets", {"select": "id"},
                          {"sha256": sha, "file_name": f.name, "photo_at": taken}, {"Prefer": "return=representation"})[0]
            (copies / f"{row['id']}.jpg").write_bytes(jpeg)
            upload(db, f"{row['id']}.jpg", jpeg)
            request(db, "PATCH", "archive_sheets", {"id": f"eq.{row['id']}"}, {"image_path": f"{row['id']}.jpg"})
            known.add(sha)
            print(f"took in {f.name} as sheet {row['id']}")
        f.rename(originals / f"{sha[:12]}-{f.name}")


def read_new(db, limit=READ_LIMIT):
    """Read up to `limit` sheets still new; a failed one is tried again after RETRY_AFTER."""
    from db import request, select
    now = datetime.now(timezone.utc)
    rows = select(db, "archive_sheets", {"select": "id,read_at", "status": "eq.new", "order": "id"})
    due = [r for r in rows if not r["read_at"] or datetime.fromisoformat(r["read_at"]) < now - RETRY_AFTER][:limit]
    for r in due:
        change = {"read_at": now.isoformat(), "model": MODEL}
        try:
            raw_text, fields = read_sheet((ROOT / "copies" / f"{r['id']}.jpg").read_bytes())
            change |= {"raw_text": raw_text, "extracted": fields, "status": "extracted", "error": None}
            print(f"sheet {r['id']}: {len(fields['lines'])} lines, out {fields['out_on']}")
        except Exception as e:  # noqa: BLE001 - one bad sheet must not stop the others
            change["error"] = f"{type(e).__name__}: {e}"[:500]
            print(f"sheet {r['id']}: {change['error']}")
        request(db, "PATCH", "archive_sheets", {"id": f"eq.{r['id']}"}, change)


def main():
    if "--file" in sys.argv:
        jpeg, taken = prepare(sys.argv[sys.argv.index("--file") + 1])
        raw_text, fields = read_sheet(jpeg)
        print(f"taken: {taken}\n--- transcription ---\n{raw_text}\n--- fields ---\n{json.dumps(fields, ensure_ascii=False, indent=2)}")
        return
    from db import connect
    db = connect()
    take_in(db)
    read_new(db)


if __name__ == "__main__":
    main()
