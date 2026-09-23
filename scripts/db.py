"""Thin PostgREST access over urllib for the batch scripts. Service key only: it bypasses RLS, so callers select explicit columns."""
import json
import os
import sys
import urllib.parse
import urllib.request

PAGE = 1000  # PostgREST's default max rows per request


def connect():
    missing = [n for n in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY") if not os.environ.get(n)]
    if missing:
        sys.exit(f"Missing environment variables: {', '.join(missing)}")
    return os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1", os.environ["SUPABASE_SERVICE_KEY"]


def request(db, method, table, params=None, body=None, headers=None):
    base, key = db
    query = "?" + urllib.parse.urlencode(params, safe=",.()") if params else ""
    req = urllib.request.Request(f"{base}/{table}{query}", method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={"apikey": key, "Authorization": f"Bearer {key}",
                                          "Content-Type": "application/json", **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return json.loads(data) if data else None


def fetch_all(get_page):
    """Every row, one PAGE at a time. get_page(start, end) returns the rows start..end inclusive."""
    rows, start = [], 0
    while True:
        page = get_page(start, start + PAGE - 1)
        rows += page
        if len(page) < PAGE:
            return rows
        start += PAGE


def select(db, table, params):
    """All rows matching PostgREST params (include an "order"), paged with Range so the 1000-row cap never truncates."""
    return fetch_all(lambda a, b: request(db, "GET", table, params, headers={"Range": f"{a}-{b}"}))


def chunks(seq, n=500):
    seq = list(seq)
    return [seq[i:i + n] for i in range(0, len(seq), n)]
