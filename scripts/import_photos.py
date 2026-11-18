"""Import embedded inventory photos. Dry run by default; use --apply to upload."""
import argparse
import hashlib
import io
import json
import re
import urllib.request
from pathlib import Path

import openpyxl
from PIL import Image, ImageOps

import db
from import_inventory import NOTE, blank, norm

SHEETS = ('Inventario Sala 15', 'Sala 1314', 'Inventario Mobiliario')
# Furniture rows counted under model names on the Sala 13/14 sheet; matched by looking at the two photos (2026-11-18).
PHOTO_ITEM = {'Projectores de teto': 'Projector NEC', 'Ecras Lenovo': 'Ecrãs Lenovo ThinkVision T2054pC'}


def thumb_path(path):
    return path.removesuffix('.jpg') + '.thumb.jpg'


def photos(path, items):
    by_name = {}
    for item in items:
        key = norm(item['name'])
        if key in by_name:
            raise ValueError(f"Ambiguous item name: {item['name']}")
        by_name[key] = item
    wb = openpyxl.load_workbook(path, data_only=True)
    seen = set()
    cells = {}
    result = []
    for sheet in SHEETS:
        ws = wb[sheet]
        furniture = sheet == 'Inventario Mobiliario'
        item_row = next((row[1].row for row in ws.iter_rows() if row[1].value == 'Item'), None) if furniture else None
        for image in ws._images:
            row, col = image.anchor._from.row + 1, image.anchor._from.col + 1
            name = ws.cell(item_row, col).value if furniture and item_row else ws.cell(row, 3).value if not furniture else None
            item = by_name.get(norm(PHOTO_ITEM.get(name, name))) if not blank(name) else None
            raw = image._data()
            digest = hashlib.sha256(raw).digest()
            if item and (item['id'], digest) in seen:
                continue
            if item:
                seen.add((item['id'], digest))
            with Image.open(io.BytesIO(raw)) as source:
                picture = ImageOps.exif_transpose(source).convert('RGB')
                picture.thumbnail((1600, 1600))
                output = io.BytesIO()
                picture.save(output, format='JPEG', quality=85)
                picture.thumbnail((400, 400))
                thumb = io.BytesIO()
                picture.save(thumb, format='JPEG', quality=80)
            slug = re.sub(r'[^a-z0-9]+', '-', norm(sheet)).strip('-')
            dest = None
            if item:
                # A cell can hold several photos: the 2nd and later get -2, -3 so none overwrites another.
                base = f"items/{item['id']}/import-{slug}-r{row}-c{col}"
                cells[base] = cells.get(base, 0) + 1
                dest = base + (f"-{cells[base]}" if cells[base] > 1 else '') + '.jpg'
            result.append({'sheet': sheet, 'row': row, 'col': col, 'item': item, 'path': dest, 'jpeg': output.getvalue(), 'thumb': thumb.getvalue()})
    return result


def upload(database, path, data):
    base, key = database
    url = base.removesuffix('/rest/v1') + '/storage/v1/object/item-photos/' + path
    req = urllib.request.Request(url, data=data, method='POST', headers={
        'Authorization': f'Bearer {key}', 'apikey': key, 'Content-Type': 'image/jpeg', 'x-upsert': 'true', 'cache-control': 'max-age=31536000'})
    with urllib.request.urlopen(req, timeout=60) as response:
        response.read()


def apply(database, pictures):
    matched = [p for p in pictures if p['item']]
    existing = {row['path'] for row in db.select(database, 'item_photos', {'select': 'path', 'order': 'id'})}
    new = [p for p in matched if p['path'] not in existing]
    for p in new:
        upload(database, p['path'], p['jpeg'])
        upload(database, thumb_path(p['path']), p['thumb'])
    if new:
        db.request(database, 'POST', 'item_photos', body=[
            {'item_id': p['item']['id'], 'path': p['path'], 'state': 'reference', 'note': NOTE} for p in new])
    print(f'new: {len(new)}, already imported: {len(matched) - len(new)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xlsx', type=Path)
    parser.add_argument('--items-json', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    database = db.connect() if args.apply or not args.items_json else None
    items = json.loads(args.items_json.read_text()) if args.items_json else db.select(database, 'items', {'select': 'id,name', 'order': 'id'})
    pictures = photos(args.xlsx, items)
    for p in pictures:
        item = p['item']
        match = f"{item['id']} {item['name']}" if item else 'UNMATCHED'
        print(f"{p['sheet']} row {p['row']} column {p['col']}: {match} {len(p['jpeg']) / 1024:.1f} KB, thumbnail {len(p['thumb']) / 1024:.1f} KB")
    matched = [p for p in pictures if p['item']]
    print(f"matched: {len(matched)}, unmatched: {len(pictures) - len(matched)}, items with photos: {len({p['item']['id'] for p in matched})}")
    if args.apply:
        apply(database, pictures)


if __name__ == '__main__':
    main()
