"""Load a scripts/backup.py folder into an project (migrations applied first).

Usage: set -a; . ./.env; set +a; uv run python scripts/restore.py ~/openlabtwin-backups/YYYY-MM-DD
audit_log is skipped: the restore itself writes fresh audit rows and replayed ids would clash with its sequence.
"""
import json
import sys
import urllib.error
from pathlib import Path

from backup import TABLES
from db import connect, request

BATCH = 500
GENERATED = {"items": {"name_norm"}}  # computed by the database; inserting them is an error
UNLINKED = {"people": {"auth_user_id"}}  # auth.users are not in the backup; staff sign in again and are re-linked


def main():
    src, db = Path(sys.argv[1]), connect()
    for t in (t for t in TABLES if t != "audit_log"):
        rows = json.loads((src / f"{t}.json").read_text(encoding="utf-8"))
        rows = [{k: v for k, v in r.items() if k not in GENERATED.get(t, ())} | dict.fromkeys(UNLINKED.get(t, ())) for r in rows]
        for i in range(0, len(rows), BATCH):
            try:
                request(db, "POST", t, None, rows[i:i + BATCH], {"Prefer": "return=minimal,resolution=merge-duplicates"})
            except urllib.error.HTTPError as e:
                sys.exit(f"{t}: {e.code} {e.read().decode()[:300]}")
        print(f"{t}: {len(rows)}")


if __name__ == "__main__":
    main()
