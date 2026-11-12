"""Export the staff-only lab catalogue to a local TyLog vault.

Usage: uv run python scripts/export_tylog.py [--data SNAPSHOT.json] [--vault DIR]
Without --vault, report a dry run and write nothing.
"""
import argparse
from collections import Counter, defaultdict
import json
import os
from pathlib import Path
import re
import tempfile
import unicodedata


def typ_str(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def tuple_str(values):
    values = list(dict.fromkeys(v for v in values if v))
    return '(' + ''.join(typ_str(v) + ', ' for v in values).rstrip() + ')'


def note(id, title, kind, aliases, properties):
    props = ', '.join(f'{key}: {tuple_str([value]) if key == "part_of" else typ_str(value)}'
                      for key, value in properties.items() if value)
    return (f'#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n'
            f'  id: {typ_str(id)},\n  title: {typ_str(title)},\n  kind: {typ_str(kind)},\n'
            f'  date: none,\n  tags: {tuple_str([kind])},\n  aliases: {tuple_str(aliases)},\n'
            f'  project: none,\n  properties: ({props}),\n)\n\n= {title}\n\n')


def build_notes(data):
    notes = {}

    def add(id, title, kind, aliases, properties):
        if not id or id in ('.', '..') or '/' in id or '\\' in id:
            raise ValueError(f'Invalid note id: {id!r}')
        if id in notes:
            raise ValueError(f'Duplicate note id: {id}')
        notes[id] = note(id, title, kind, aliases, {**properties, 'source': 'openlabtwin'})

    places = {p['id']: p for p in data['places']}
    for p in data['places']:
        if p['code']:
            parent = places.get(p['parent_id']) or {}
            add(p['code'], p['name'], 'place', [p['name'], p['code']], {'part_of': parent.get('code')})

    items = {i['id']: i['name'] for i in data['items']}
    locations = {row['asset_id']: row['place_id'] for row in data['asset_place']}
    groups = defaultdict(list)
    for asset in data['assets']:
        groups[asset['item_id']].append(asset)
    for item_id, assets in groups.items():
        assets.sort(key=lambda a: a['tag'])
        numbers = []
        for rank, a in enumerate(assets, 1):
            digits = ''.join(re.findall(r'\d', a['tag']))
            numbers.append(rank if a['tag'].startswith('TL-') else (int(digits) if digits else None))
        counts = Counter(numbers)
        for a, number in zip(assets, numbers):
            tag, name = a['tag'], items[item_id]
            aliases = [tag, tag.replace('-', ''), a['serial']]
            if number is not None and counts[number] == 1:
                aliases += [f'{name} {number}', f'{name} no. {number}', f'{name} nº {number}']
            place = places.get(locations.get(a['id'])) or {}
            add(tag, f'{name} {tag}', 'equipment', aliases,
                {'part_of': place.get('code'), 'serial': a['serial'], 'status': a['condition'],
                 'tag': tag, 'item': name})
    for p in data['people']:
        if p['kind'] == 'professor':
            folded = unicodedata.normalize('NFKD', p['name']).encode('ascii', 'ignore').decode('ascii')
            add(f"lab-person-{p['id']}", p['name'], 'person', [p['name'], folded], {})
    return notes


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='\n', dir=path.parent, delete=False) as f:
            name = f.name
            f.write(content)
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


def write_notes(directory, notes, dry_run=False):
    directory = Path(directory)
    new = changed = unchanged = 0
    for id, content in notes.items():
        path = directory / f'{id}.typ'
        old = path.read_text(encoding='utf-8') if path.exists() else None
        if old is None:
            new += 1
        elif old != content:
            changed += 1
        else:
            unchanged += 1
        if not dry_run and old != content:
            atomic_write(path, content)
    orphans = sorted(p.name for p in directory.glob('*.typ') if p.stem not in notes
                     and 'source: "openlabtwin"' in p.read_text(encoding='utf-8'))
    return new, changed, unchanged, orphans


def merge_kinds(path):
    path = Path(path)
    kinds = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    if 'equipment' not in kinds:
        kinds['equipment'] = {'icon': 'build', 'label': 'Equipment'}
        atomic_write(path, json.dumps(kinds, ensure_ascii=False, indent=2) + '\n')
    return kinds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path)
    parser.add_argument('--vault', type=Path)
    args = parser.parse_args()
    if args.vault and not (args.vault / '_system').is_dir():
        parser.error('vault must contain a _system directory')
    if args.vault and args.vault.resolve().is_relative_to(Path(__file__).resolve().parent.parent):
        parser.error('staff-only catalogue must not be written inside the repository')
    if args.data:
        data = json.loads(args.data.read_text(encoding='utf-8'))
    else:
        import db
        conn = db.connect()
        columns = {'places': 'id,code,name,parent_id', 'assets': 'id,tag,serial,condition,item_id',
                   'items': 'id,name', 'asset_place': 'asset_id,place_id', 'people': 'id,name,kind'}
        data = {table: db.select(conn, table, {'select': cols, 'order': 'asset_id' if table == 'asset_place' else 'id'})
                for table, cols in columns.items()}
    try:
        notes = build_notes(data)
    except ValueError as exc:
        parser.error(str(exc))
    if args.vault:
        result = write_notes(args.vault / 'notes/labs/inventory', notes)
        merge_kinds(args.vault / '_system/settings/kinds.json')
    else:
        result = (len(notes), 0, 0, [])
    new, changed, unchanged, orphans = result
    for orphan in orphans:
        print(f'Orphan: {orphan}')
    print(f'{new} new / {changed} changed / {unchanged} unchanged / {len(orphans)} orphans' +
          ('' if args.vault else ' (dry run)'))


if __name__ == '__main__':
    main()
