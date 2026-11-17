"""Run: uv run python tests/test_export_tylog.py"""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
import export_tylog as export  # noqa: E402


data = {
    'places': [{'id': 1, 'code': 'LAB', 'name': 'Lab', 'parent_id': None},
               {'id': 2, 'code': 'SHELF', 'name': 'Shelf', 'parent_id': 1}],
    'items': [{'id': 1, 'name': 'VR glasses'}, {'id': 2, 'name': 'Camera'}],
    'assets': [{'id': n, 'tag': f'TL-{n:04}', 'serial': 'ABC' if n == 3 else None,
                'condition': 'good', 'item_id': 1} for n in range(1, 4)] + [
        {'id': 4, 'tag': 'LV-01', 'serial': None, 'condition': 'good', 'item_id': 2},
        {'id': 5, 'tag': 'XX-01', 'serial': None, 'condition': 'good', 'item_id': 2}],
    'asset_place': [{'asset_id': 3, 'place_id': 2}, {'asset_id': 1, 'place_id': None}],
    'people': [{'id': 7, 'name': 'José Silva', 'kind': 'professor', 'email': 'prof@example.com'},
               {'id': 8, 'name': 'Student Secret', 'kind': 'student', 'email': 'student@example.com'},
               {'id': 9, 'name': 'Staff Secret', 'kind': 'staff', 'email': 'staff@example.com'}],
}
notes = export.build_notes(data)


def test_export_unchanged_data_is_byte_identical():
    with tempfile.TemporaryDirectory() as tmp:
        inventory = Path(tmp) / 'inventory'
        export.write_notes(inventory, export.build_notes(data))
        first = {p.name: p.read_bytes() for p in inventory.iterdir()}
        assert export.write_notes(inventory, export.build_notes(data)) == (0, 0, len(notes), [])
        assert first == {p.name: p.read_bytes() for p in inventory.iterdir()}


def test_unique_item_keeps_plain_title_and_name():
    unique = copy.deepcopy(data)
    unique['assets'] = [unique['assets'][3]]
    generated = export.build_notes(unique)['LV-01']
    assert 'title: "Camera LV-01"' in generated
    assert 'item: "Camera"' in generated
    assert '"Camera [1]"' not in generated


assert export.equipment_aliases('Camera', 'LV-01', ['Camera']) == ['Camera', 'LV-01']
assert export.equipment_aliases('Camera', 'LV-03', ['Camera', 'Camera', 'Camera'], 3) == [
    'Camera 3', 'Camera num3', 'Camera no. 3', 'Camera #3', 'LV-03']
assert export.equipment_aliases('VR glasses 3', 'TL-0003', ['VR glasses 3']) == [
    'VR glasses 3', 'TL-0003', 'vr-glasses-3']
for suffix in ('[1]', '(1)', '#1', '№1', 'no. 1', 'nº 1', 'n1', 'unit 1'):
    item, unit = export.split_unit(f'QUEST 3 {suffix.upper()}')
    assert (item, unit) == ('QUEST 3', 1)
    aliases = export.equipment_aliases(item, 'TL-0201', [item], 1, unit)
    assert aliases == ['QUEST 3 [1]', 'QUEST 3', 'TL-0201', 'quest-3']
    explicit = copy.deepcopy(data)
    explicit['items'] = [{'id': 1, 'name': f'QUEST 3 {suffix}'}]
    explicit['assets'] = [{'id': 1, 'tag': 'TL-0201', 'serial': None, 'condition': 'good', 'item_id': 1}]
    generated = export.build_notes(explicit)['TL-0201']
    assert 'title: "QUEST 3 unit 1 TL-0201"' in generated
    assert 'item: "QUEST 3"' in generated and '"QUEST 3 [1]"' in generated
assert export.split_unit('Quest 3') == ('Quest 3', None)
assert export.typ_str('a\\b"c\nd') == '"a\\\\b\\"c\\nd"'
assert notes['TL-0003'] == '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "TL-0003",
  title: "VR glasses unit 3 TL-0003",
  kind: "equipment",
  date: none,
  tags: ("equipment",),
  aliases: ("VR glasses [3]", "VR glasses 3", "VR glasses num3", "VR glasses no. 3", "VR glasses #3", "VR-glasses 3", "VR-glasses num3", "VR-glasses no. 3", "VR-glasses #3", "TL-0003",),
  project: none,
  properties: (part_of: ("SHELF",), serial: "ABC", status: "good", tag: "TL-0003", item: "VR glasses", source: "openlabtwin"),
)

= VR glasses unit 3 TL-0003

'''
assert notes['SHELF'] == '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "SHELF",
  title: "Shelf",
  kind: "place",
  date: none,
  tags: ("place",),
  aliases: ("Shelf", "SHELF",),
  project: none,
  properties: (part_of: ("LAB",), source: "openlabtwin"),
)

= Shelf

'''
assert notes['lab-person-7'] == '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "lab-person-7",
  title: "José Silva",
  kind: "person",
  date: none,
  tags: ("person",),
  aliases: ("José Silva", "Jose Silva",),
  project: none,
  properties: (source: "openlabtwin"),
)

= José Silva

'''
assert not any(s in ''.join(notes.values()) for s in ['Student Secret', 'Staff Secret', '@example.com'])
assert '"Camera 1"' in notes['LV-01'] and '"Camera 2"' in notes['XX-01']  # same-named assets are numbered by tag order
assert 'title: "Camera unit 1 LV-01"' in notes['LV-01']
assert 'item: "Camera"' in notes['LV-01']
mixed = copy.deepcopy(data)
mixed['items'] = [{'id': 1, 'name': 'QUEST 3 [1]'}, {'id': 2, 'name': 'QUEST 3'}]
mixed['assets'] = [
    {'id': 1, 'tag': 'TL-0201', 'serial': None, 'condition': 'good', 'item_id': 1},
    {'id': 2, 'tag': 'TL-0202', 'serial': None, 'condition': 'good', 'item_id': 2},
]
mixed_notes = export.build_notes(mixed)
assert 'title: "QUEST 3 unit 1 TL-0201"' in mixed_notes['TL-0201']
assert 'title: "QUEST 3 unit 2 TL-0202"' in mixed_notes['TL-0202']
assert '"QUEST 3 [2]"' in mixed_notes['TL-0202']
assert 'aliases: ("QUEST 3 [2]"' in mixed_notes['TL-0202']
assert '"QUEST 3 unit 2 TL-0202"' not in mixed_notes['TL-0202'].split('aliases: (', 1)[1].split('),', 1)[0]
assert 'title: "Camera unit 1 LV-01"' in notes['LV-01']
assert 'item: "Camera"' in notes['LV-01']
assert 'part_of:' not in notes['TL-0001']
bad = copy.deepcopy(data)
bad['places'][0]['code'] = 'TL-0003'
try:
    export.build_notes(bad)
    assert False, 'duplicate id accepted'
except ValueError:
    pass

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    inventory = root / 'notes/labs/inventory'
    assert export.write_notes(inventory, notes) == (len(notes), 0, 0, [])
    first_bytes = {p.name: p.read_bytes() for p in inventory.iterdir()}
    mtimes = {p.name: p.stat().st_mtime_ns for p in inventory.iterdir()}
    assert export.write_notes(inventory, notes) == (0, 0, len(notes), [])
    assert first_bytes == {p.name: p.read_bytes() for p in inventory.iterdir()}
    assert mtimes == {p.name: p.stat().st_mtime_ns for p in inventory.iterdir()}
    changed = copy.deepcopy(data)
    changed['asset_place'][0]['place_id'] = 1
    assert export.write_notes(inventory, export.build_notes(changed)) == (0, 1, len(notes) - 1, [])
    assert all((inventory / name).stat().st_mtime_ns == stamp for name, stamp in mtimes.items() if name != 'TL-0003.typ')
    # Aliases and colour the user added in TyLog survive a re-export.
    export.write_notes(inventory, notes)
    path = inventory / 'TL-0002.typ'
    edited = path.read_text(encoding='utf-8')
    edited = edited.replace('"TL-0002",)', '"TL-0002", "yellow \\"glasses\\"", "жёлтый шлем",)')
    edited = edited.replace(', source: "openlabtwin"', ', color: "yellow", source: "openlabtwin"')
    path.write_text(edited, encoding='utf-8')
    assert export.write_notes(inventory, notes) == (0, 0, len(notes), [])
    assert path.read_text(encoding='utf-8') == edited  # byte-identical: nothing to change
    # A removed generated alias comes back; user extras follow generated ones, order stable.
    path.write_text(edited.replace('"VR glasses 2", ', ''), encoding='utf-8')
    export.write_notes(inventory, notes)
    assert path.read_text(encoding='utf-8') == edited
    # Source-provided colour wins over the user's.
    withcolor = {**notes, 'TL-0002': notes['TL-0002'].replace(', source:', ', color: "blue", source:')}
    export.write_notes(inventory, withcolor)
    assert 'color: "blue"' in path.read_text(encoding='utf-8') and 'color: "yellow"' not in path.read_text(encoding='utf-8')
    path.write_text(edited, encoding='utf-8')
    orphan = inventory / 'old.typ'
    orphan.write_text('source: "openlabtwin"', encoding='utf-8')
    assert export.write_notes(inventory, notes)[3] == ['old.typ'] and orphan.exists()
    kinds = root / '_system/settings/kinds.json'
    kinds.parent.mkdir(parents=True)
    kinds.write_text(json.dumps({'place': {'icon': 'home'}}), encoding='utf-8')
    assert export.merge_kinds(kinds) == {'place': {'icon': 'home'}, 'equipment': {'icon': 'build', 'label': 'Equipment'}}
    before = kinds.read_bytes()
    export.merge_kinds(kinds)
    assert kinds.read_bytes() == before

    repo = Path(os.environ.get('TYLOG_REPO', Path.home() / 'Documents/GitHub/TypstSeq')).expanduser()
    if shutil.which('typst') and repo.is_dir():
        system = root / '_system'
        for name in ('tylog.typ', 'theme.typ'):
            shutil.copy(repo / 'typst/vault' / name, system / name)
        package = system / 'packages/tylog/0.1.0'
        package.mkdir(parents=True)
        for name in ('lib.typ', 'typst.toml'):
            shutil.copy(repo / 'typst/tylog' / name, package / name)
        for id in notes:
            result = subprocess.run(['typst', 'compile', '--root', str(root), str(inventory / f'{id}.typ'),
                                     str(root / 'out.pdf')], capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
    else:
        print('skip typst')
print('ok')
