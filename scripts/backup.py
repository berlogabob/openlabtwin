"""Nightly off-site backup: every table as JSON under a dated folder. The Supabase free plan keeps no backups.

Usage: uv run python scripts/backup.py [dir]      (default ~/openlabtwin-backups; keeps the newest KEEP days)
The files hold private data (emails, purposes), so the folder is created mode 700 and lives outside the repo.
Restore: insert each table's rows back in TABLES order (parents first) with the service key.
"""
import json
import os
import sys
from datetime import date
from pathlib import Path

from db import connect, select

TABLES = ["places", "items", "people", "organizations", "consultation_hours", "activities", "activity_items", "movements", "lessons",
          "audit_log"]  # parents before children
KEEP = 30


def prune(days, keep):
    """Dated folder names (YYYY-MM-DD) to delete so only the newest `keep` remain."""
    return sorted(days)[:-keep] if len(days) > keep else []


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "openlabtwin-backups")
    out = root / date.today().isoformat()
    out.mkdir(parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    db = connect()
    for t in TABLES:
        rows = select(db, t, {"select": "*", "order": "id" if t != "activity_items" else "activity_id,item_id"})
        (out / f"{t}.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        print(f"{t}: {len(rows)}")
    for old in prune([p.name for p in root.iterdir() if p.is_dir() and len(p.name) == 10], KEEP):
        for f in (root / old).iterdir():
            f.unlink()
        (root / old).rmdir()
        print(f"pruned {old}")


if __name__ == "__main__":
    main()
