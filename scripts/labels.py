"""Printable QR labels for places and assets: an A4 HTML page, 3 × 8 labels, each QR opening the office at that place.

Usage: uv run python scripts/labels.py [--root CODE] [--assets] [--out FILE]
  --root CODE   only that place and everything under it (default: every place with a code)
  --assets      asset tags instead (the QR opens the place the asset lives in)
  --out FILE    default ~/Downloads/labels.html; open it in a browser and print at 100 %.
Staff-only data (where each asset is), so the page is written locally, never to the repo or the site.
"""
import html
import sys
from pathlib import Path

import segno

OFFICE = "https://berlogabob.github.io/openlabtwin/office/"


def place_url(code):
    return f"{OFFICE}?place={code}"


def subtree(places, root):
    """Places under (and including) the one with code `root`, parents before children."""
    kids = {}
    for p in places:
        kids.setdefault(p["parent_id"], []).append(p)
    start = [p for p in places if p["code"] == root] if root else [p for p in places if p["parent_id"] is None]
    out, stack = [], list(reversed(start))
    while stack:
        p = stack.pop()
        out.append(p)
        stack += reversed(sorted(kids.get(p["id"], []), key=lambda k: k["code"] or ""))
    return [p for p in out if p["code"]]


def label_html(labels):
    """labels: (big text, small text, url) triples -> one printable page."""
    cells = "".join(
        f'<div class="l">{segno.make(url, error="m").svg_inline(scale=3, border=0)}'
        f'<div><b>{html.escape(big)}</b><span>{html.escape(small)}</span></div></div>'
        for big, small, url in labels)
    return ("<!doctype html><meta charset=utf-8><title>Labels</title><style>"
            "@page{size:A4;margin:10mm}body{margin:0;font:11px system-ui,sans-serif}"
            ".g{display:grid;grid-template-columns:repeat(3,1fr);grid-auto-rows:34mm;gap:0}"
            ".l{display:flex;gap:3mm;align-items:center;padding:3mm;border:1px dashed #bbb;break-inside:avoid;overflow:hidden}"
            ".l svg{width:26mm;height:26mm;flex:none}b{display:block;font-size:16px;letter-spacing:.5px}span{color:#444}"
            f'</style><div class="g">{cells}</div>')


def main():
    from db import connect, select
    args = sys.argv[1:]
    root = args[args.index("--root") + 1] if "--root" in args else None
    out = Path(args[args.index("--out") + 1] if "--out" in args else Path.home() / "Downloads/labels.html")
    db = connect()
    places = select(db, "places", {"select": "id,code,name,parent_id", "order": "id"})
    chosen = subtree(places, root)
    if "--assets" in args:
        where = {w["asset_id"]: w["place_id"] for w in select(db, "asset_place", {"select": "asset_id,place_id", "order": "asset_id"})}
        codes = {p["id"]: p["code"] for p in chosen}
        rows = select(db, "assets", {"select": "id,tag,items(name)", "order": "tag"})
        labels = [(a["tag"], a["items"]["name"], place_url(codes[where[a["id"]]])) for a in rows if where.get(a["id"]) in codes]
    else:
        labels = [(p["code"], p["name"], place_url(p["code"])) for p in chosen]
    out.write_text(label_html(labels), encoding="utf-8")
    print(f"{len(labels)} labels -> {out}")


if __name__ == "__main__":
    main()
