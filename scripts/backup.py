"""Nightly off-site backup: every table as JSON under a dated folder. The Supabase free plan keeps no backups.

Usage: uv run python scripts/backup.py [dir]      (default ~/openlabtwin-backups; keeps the newest KEEP days)
The files hold private data (emails, purposes), so the folder is created mode 700 and lives outside the repo.
One request per new photo file, normally a handful a day, fits decision 0051's request budget.
Restore photos by uploading root/photos back to the item-photos bucket.
Restore: insert each table's rows back in TABLES order (parents first) with the service key.
"""
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

from db import connect, select

TABLES = ["places", "items", "people", "organizations", "consultation_hours", "activities", "activity_items", "assets", "item_photos", "movements",
          "issue_waivers", "archive_sheets", "archive_loans", "lessons",
          "ideas", "idea_skills", "idea_matches", "tv_media", "tv_slides", "wall_slides", "wall_state", "audit_log"]  # parents before children
SKIP = {"tv_status", "wall_status"}  # heartbeat rows rewritten every few minutes, nothing to restore
ORDER = {"activity_items": "activity_id,item_id", "issue_waivers": "key", "idea_skills": "idea_id,side,phrase",
         "idea_matches": "idea_a,idea_b,kind", "tv_media": "name"}  # tables without an id column
KEEP = 30


def thumb_path(path):
    return path.removesuffix(".jpg") + ".thumb.jpg"  # same rule as import_photos.py and the office


def prune(days, keep):
    """Dated folder names (YYYY-MM-DD) to delete so only the newest `keep` remain."""
    return sorted(days)[:-keep] if len(days) > keep else []


def copy_photos(rows, dest, fetch):
    copied = missing = 0
    for row in rows:
        for path in (row["path"], thumb_path(row["path"])):
            target = dest / path
            if target.exists():
                continue
            data = fetch(path)
            if data is None:
                missing += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as tmp:
                try:
                    tmp.write(data)
                    tmp.close()
                    os.replace(tmp.name, target)
                finally:
                    Path(tmp.name).unlink(missing_ok=True)
            copied += 1
    return copied, missing


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "openlabtwin-backups")
    out = root / date.today().isoformat()
    out.mkdir(parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    db = connect()
    photo_rows = []
    for t in TABLES:
        rows = select(db, t, {"select": "*", "order": ORDER.get(t, "id")})
        (out / f"{t}.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        print(f"{t}: {len(rows)}")
        if t == "item_photos":
            photo_rows = rows

    def fetch(path):
        base, key = db
        url = base.removesuffix("/rest/v1") + "/storage/v1/object/authenticated/item-photos/" + path
        req = urllib.request.Request(url, headers={"apikey": key, "Authorization": f"Bearer {key}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise

    copied, missing = copy_photos(photo_rows, root / "photos", fetch)
    print(f"photos: copied {copied}, missing {missing}")
    for old in prune([p.name for p in root.iterdir() if p.is_dir() and len(p.name) == 10], KEEP):
        for f in (root / old).iterdir():
            f.unlink()
        (root / old).rmdir()
        print(f"pruned {old}")


if __name__ == "__main__":
    main()
