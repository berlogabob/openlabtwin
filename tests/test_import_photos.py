"""Run: uv run python tests/test_import_photos.py"""
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import openpyxl
from openpyxl.drawing.image import Image as XLImage
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
import import_photos as imp

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    img = root / 'image.png'
    Image.new('RGB', (2000, 1000), 'red').save(img)
    blue = root / 'blue.png'
    Image.new('RGB', (2000, 1000), 'blue').save(blue)
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Inventario Sala 15'
    ws['C2'] = 'Câbos Ethernet'
    ws['C3'] = 'Cabos Ethernet'
    ws.add_image(XLImage(img), 'H2')
    ws.add_image(XLImage(img), 'H3')
    ws.add_image(XLImage(blue), 'H2')  # a second, different photo in the same cell
    wb.create_sheet('Sala 1314')
    furniture = wb.create_sheet('Inventario Mobiliario')
    furniture['B4'] = 'Item'
    furniture['D4'] = 'Mesa'
    furniture.add_image(XLImage(img), 'D3')
    xlsx = root / 'test.xlsx'
    wb.save(xlsx)
    items = [{'id': 42, 'name': 'Cabos ethernet'}, {'id': 43, 'name': 'Mesa'}]
    items_file = root / 'items.json'
    items_file.write_text(json.dumps(items))
    output = subprocess.check_output([sys.executable, 'scripts/import_photos.py', str(xlsx), '--items-json', str(items_file)], text=True)
    assert '42 Cabos ethernet' in output and 'matched: 3, unmatched: 0, items with photos: 2' in output
    pictures = imp.photos(xlsx, items)
    assert len(pictures) == 3
    assert pictures[1]['path'] == 'items/42/import-inventario-sala-15-r2-c8-2.jpg'
    assert pictures[2]['path'] == 'items/43/import-inventario-mobiliario-r3-c4.jpg'
    assert Image.open(io.BytesIO(pictures[0]['jpeg'])).size == (1600, 800)
    assert Image.open(io.BytesIO(pictures[0]['thumb'])).size == (400, 200)
    uploaded, rows = [], []
    imp.upload = lambda db, path, data: uploaded.append((path, data))
    imp.db.select = lambda *args: rows
    imp.db.request = lambda db, method, table, **kw: rows.extend(kw['body'])
    imp.apply(('fake', 'key'), pictures[:1])
    path = 'items/42/import-inventario-sala-15-r2-c8.jpg'
    assert uploaded == [(path, pictures[0]['jpeg']), (path.removesuffix('.jpg') + '.thumb.jpg', pictures[0]['thumb'])]
    assert rows == [{'item_id': 42, 'path': path, 'state': 'reference', 'note': imp.NOTE}]
    try:
        imp.apply(('fake', 'key'), pictures)
        assert False, 'second import should fail'
    except ValueError:
        pass
    assert len(uploaded) == 2
print('ok')
