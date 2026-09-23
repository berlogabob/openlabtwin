"""Thin Supabase access for the batch scripts. Service key only: it bypasses RLS, so callers select explicit columns."""
import os
import sys

PAGE = 1000  # PostgREST's default max rows per request


def connect():
    missing = [n for n in ("SUPABASE_URL", "SUPABASE_SERVICE_KEY") if not os.environ.get(n)]
    if missing:
        sys.exit(f"Missing environment variables: {', '.join(missing)}")
    from supabase import create_client  # imported here so the pure tests don't need network setup

    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def fetch_all(query_factory):
    """Every row of a query, one PAGE at a time. query_factory() must return a fresh builder with an .order()."""
    rows, start = [], 0
    while True:
        page = query_factory().range(start, start + PAGE - 1).execute().data or []
        rows += page
        if len(page) < PAGE:
            return rows
        start += PAGE


def chunks(seq, n=500):
    seq = list(seq)
    return [seq[i:i + n] for i in range(0, len(seq), n)]
