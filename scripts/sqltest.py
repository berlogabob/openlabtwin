"""Migrations + pgTAP tests over HTTPS only (Supabase Management API). No Docker, no Postgres port needed.

Usage: uv run python scripts/sqltest.py            push pending migrations, then run every test
       uv run python scripts/sqltest.py --seed     also load supabase/seed.sql once

Each API call runs as one transaction. A test file ends by raising an exception that carries its TAP lines,
which rolls back everything the test did and brings the results back in the error message.
Auth: SUPABASE_ACCESS_TOKEN, else the token `supabase login` put in the macOS keychain.
Project: SUPABASE_PROJECT_REF, else supabase/.temp/project-ref (written by `supabase link`).
"""
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase/migrations"
TESTS = ROOT / "supabase/tests/database"
# pgTAP 1.3 keeps only counters, not result lines, so every top-level select is captured into __tap.
CAPTURE = """
create temp table __tap (n serial, line text);
grant insert on __tap to public;
grant usage on sequence __tap_n_seq to public;
"""
REPORT = """
insert into __tap (line) select * from finish();
reset role;
do $tap$ begin
  raise exception 'TAP%', E'\\n' || (select string_agg(line, E'\\n' order by n) from __tap
                                   where line ~ '^(ok|not ok|#|1\\.\\.)');
end $tap$;
"""


def token():
    if os.environ.get("SUPABASE_ACCESS_TOKEN"):
        return os.environ["SUPABASE_ACCESS_TOKEN"]
    raw = subprocess.run(["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                         capture_output=True, text=True, check=True).stdout.strip()
    raw = raw.removeprefix("go-keyring-base64:")
    return raw if raw.startswith("sbp_") else base64.b64decode(raw).decode()


def project_ref():
    return os.environ.get("SUPABASE_PROJECT_REF") or (ROOT / "supabase/.temp/project-ref").read_text().strip()


def query(sql):
    """Run SQL; return (rows, None) or (None, error message)."""
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{project_ref()}/database/query",
        data=json.dumps({"query": sql}).encode(), method="POST",
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return None, json.loads(body).get("message", body)
        except ValueError:
            return None, body


def lit(s):
    return "'" + s.replace("'", "''") + "'"


def push_migrations():
    rows, err = query("create schema if not exists supabase_migrations;"
                      "create table if not exists supabase_migrations.schema_migrations"
                      " (version text primary key, statements text[], name text);"
                      "select version from supabase_migrations.schema_migrations")
    if err:
        sys.exit(f"Cannot read migration history: {err}")
    done = {r["version"] for r in rows}
    for f in sorted(MIGRATIONS.glob("*.sql")):
        version, _, name = f.stem.partition("_")
        if version in done:
            continue
        sql = f.read_text(encoding="utf-8")
        record = (f"insert into supabase_migrations.schema_migrations (version, name, statements)"
                  f" values ({lit(version)}, {lit(name)}, array[{lit(sql)}]);")
        _, err = query(sql + "\n;\n" + record)  # one request = one transaction: applied and recorded together
        if err:
            sys.exit(f"✗ migration {f.name}: {err}")
        print(f"applied {f.name}")


def run_test(f):
    body = f.read_text(encoding="utf-8")
    body = re.sub(r"(?im)^\s*(begin|rollback)\s*;\s*$", "", body)
    body = re.sub(r"(?im)^select \* from finish\(\)\s*;\s*$", "-- finish", body)
    body = re.sub(r"(?m)^select ", "insert into __tap (line) select ", body)  # unindented = top-level test call
    _, err = query(CAPTURE + body.replace("-- finish", REPORT))
    m = re.search(r"TAP\n(.*?)(?:\nCONTEXT:|$)", err or "", re.S)
    if not m:
        return False, err or "test did not report (missing 'select * from finish();'?)"
    tap = m.group(1).strip()
    return not re.search(r"^not ok|Looks like", tap, re.M), tap


def main():
    push_migrations()
    if "--seed" in sys.argv:
        _, err = query((ROOT / "supabase/seed.sql").read_text(encoding="utf-8"))
        sys.exit(f"✗ seed: {err}") if err else print("seeded")
    failed = 0
    for f in sorted(TESTS.glob("*.sql")):
        ok, tap = run_test(f)
        passed = len(re.findall(r"^ok ", tap, re.M))
        print(f"✓ {f.name} ({passed} passed)" if ok else f"✗ {f.name}\n{tap}")
        failed += not ok
    sys.exit(1 if failed else 0)


TOKEN = token()
if __name__ == "__main__":
    main()
