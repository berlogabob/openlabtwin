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


def photos(path, items):
    by_name = {}
    for item in items:
        key = norm(item['name'])
        if key in by_name:
            raise ValueError(f"Ambiguous item name: {item['name']}")
        by_name[key] = item
    wb = openpyxl.load_workbook(path, data_only=True)
    seen = set()
    result = []
    for sheet in SHEETS:
        ws = wb[sheet]
        furniture = sheet == 'Inventario Mobiliario'
        item_row = next((row[1].row for row in ws.iter_rows() if row[1].value == 'Item'), None) if furniture else None
        for image in ws._images:
            row, col = image.anchor._from.row + 1, image.anchor._from.col + 1
            name = ws.cell(item_row, col).value if furniture and item_row else ws.cell(row, 3).value if not furniture else None
            item = by_name.get(norm(name)) if not blank(name) else None
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
            slug = re.sub(r'[^a-z0-9]+', '-', norm(sheet)).strip('-')
            dest = f"items/{item['id']}/import-{slug}-r{row}-c{col}.jpg" if item else None
            result.append({'sheet': sheet, 'row': row, 'col': col, 'item': item, 'path': dest, 'jpeg': output.getvalue()})
    return result


def upload(database, path, data):
    base, key = database
    url = base.removesuffix('/rest/v1') + '/storage/v1/object/item-photos/' + path
    req = urllib.request.Request(url, data=data, method='POST', headers={
        'Authorization': f'Bearer {key}', 'apikey': key, 'Content-Type': 'image/jpeg', 'x-upsert': 'false'})
    with urllib.request.urlopen(req, timeout=60) as response:
        response.read()


def apply(database, pictures):
    if db.select(database, 'item_photos', {'select': 'id', 'note': f'eq.{NOTE}', 'order': 'id'}):
        raise ValueError('Already imported: item photos with the import note exist.')
    matched = [p for p in pictures if p['item']]
    for p in matched:
        upload(database, p['path'], p['jpeg'])
    if matched:
        db.request(database, 'POST', 'item_photos', body=[
            {'item_id': p['item']['id'], 'path': p['path'], 'state': 'reference', 'note': NOTE} for p in matched])


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
        print(f"{p['sheet']} row {p['row']} column {p['col']}: {match} {len(p['jpeg']) / 1024:.1f} KB")
    matched = [p for p in pictures if p['item']]
    print(f"matched: {len(matched)}, unmatched: {len(pictures) - len(matched)}, items with photos: {len({p['item']['id'] for p in matched})}")
    if args.apply:
        apply(database, pictures)


if __name__ == '__main__':
    main()
