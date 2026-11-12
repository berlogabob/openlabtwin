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
assert export.equipment_aliases('Camera', 'LV-01', ['Camera']) == ['Camera', 'LV-01']
assert export.equipment_aliases('Camera', 'LV-03', ['Camera', 'Camera', 'Camera'], 3) == [
    'Camera 3', 'Camera num3', 'Camera no. 3', 'Camera #3', 'LV-03']
assert export.equipment_aliases('VR glasses 3', 'TL-0003', ['VR glasses 3']) == [
    'VR glasses 3', 'TL-0003', 'vr-glasses-3']
assert export.typ_str('a\\b"c\nd') == '"a\\\\b\\"c\\nd"'
assert notes['TL-0003'] == '''#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(
  id: "TL-0003",
  title: "VR glasses TL-0003",
  kind: "equipment",
  date: none,
  tags: ("equipment",),
  aliases: ("VR glasses 3", "VR glasses num3", "VR glasses no. 3", "VR glasses #3", "VR-glasses 3", "VR-glasses num3", "VR-glasses no. 3", "VR-glasses #3", "TL-0003",),
  project: none,
  properties: (part_of: ("SHELF",), serial: "ABC", status: "good", tag: "TL-0003", item: "VR glasses", source: "openlabtwin"),
)

= VR glasses TL-0003

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
    mtimes = {p.name: p.stat().st_mtime_ns for p in inventory.iterdir()}
    assert export.write_notes(inventory, notes) == (0, 0, len(notes), [])
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
