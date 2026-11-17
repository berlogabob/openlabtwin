import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/data.dart';
import 'package:office/item_page.dart';
import 'package:office/scan_screen.dart';
import 'package:office/places.dart';

void main() {
  test('thumbnail path follows the photo path', () {
    expect(thumbPath('items/3/1-ab.jpg'), 'items/3/1-ab.thumb.jpg');
  });

  final refs = Refs(
    [
      {'id': 1, 'name': 'Shelf', 'code': 'S1'},
      {'id': 5, 'name': 'Other', 'code': 'S2'},
    ],
    [
      {'id': 2, 'name': 'Ana'},
    ],
    [],
    [
      {'id': 3, 'name': 'Camera', 'kind': 'portable'},
    ],
    [
      {'id': 4, 'item_id': 3, 'tag': 'GS-031'},
    ],
    9,
  );
  Rec expected(
    String kind, {
    int? from,
    int? to,
    int? person,
    int? asset,
    num qty = 1,
  }) => {
    'kind': kind,
    'item_id': 3,
    'qty': qty,
    'from_place': from,
    'to_place': to,
    'person_id': person,
    'activity_id': null,
    'by_staff': 9,
    'asset_id': asset,
    'note': null,
  };
  Future<void> choose(WidgetTester t, String label, String value) async {
    await t.tap(find.widgetWithText(TextField, label));
    await t.pumpAndSettle();
    await t.tap(find.text(value).last);
    await t.pumpAndSettle();
  }

  void noVerbs() {
    for (final word in ['issue', 'receive', 'adjust', 'consume']) {
      expect(find.text(word), findsNothing);
    }
  }

  testWidgets('tagged hand out', (t) async {
    List<Rec>? written;
    await t.pumpWidget(
      MaterialApp(
        home: AssetPage(
          refs: refs,
          asset: refs.assets.first,
          loadPlaces: () async => [
            {'asset_id': 4, 'place_id': 1},
          ],
          loadHistory: () async => [],
          save: (rows) async {
            written = rows;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Take back'), findsNothing);
    await t.tap(find.text('Hand out'));
    await t.pumpAndSettle();
    noVerbs();
    await choose(t, 'Person', 'Ana');
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(written, [expected('issue', from: 1, person: 2, asset: 4)]);
  });
  testWidgets('tagged take back uses last shelf', (t) async {
    List<Rec>? written;
    await t.pumpWidget(
      MaterialApp(
        home: AssetPage(
          refs: refs,
          asset: refs.assets.first,
          loadPlaces: () async => [
            {'asset_id': 4, 'person_id': 2},
          ],
          loadHistory: () async => [
            {'kind': 'issue', 'from_place': 1},
          ],
          save: (rows) async {
            written = rows;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Hand out'), findsNothing);
    expect(find.text('Move'), findsNothing);
    await t.tap(find.text('Take back'));
    await t.pumpAndSettle();
    noVerbs();
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(written, [expected('return', to: 1, person: 2, asset: 4)]);
  });
  testWidgets('untagged move of five', (t) async {
    List<Rec>? written;
    await t.pumpWidget(
      MaterialApp(
        home: ItemPage(
          refs: refs,
          item: refs.items.first,
          loader: () async => (
            [
              {'item_id': 3, 'place_id': 1, 'qty': 10},
            ],
            <Rec>[],
            <Rec>[],
            <Rec>[],
          ),
          save: (rows) async {
            written = rows;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Move'));
    await t.pumpAndSettle();
    noVerbs();
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '5');
    await choose(t, 'To', 'S2 · Other');
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(written, [expected('move', from: 1, to: 5, qty: 5)]);
  });
  testWidgets('consumable switch writes both kinds', (t) async {
    final item = <String, dynamic>{'id': 3, 'name': 'Camera', 'kind': 'stationary'};
    final kinds = <String>[];
    await t.pumpWidget(MaterialApp(home: ItemPage(
      refs: refs, item: item,
      loader: () async => (<Rec>[], <Rec>[], <Rec>[], <Rec>[]),
      saveKind: (id, kind) async { kinds.add(kind); },
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Consumable'));
    await t.pumpAndSettle();
    await t.tap(find.text('Consumable'));
    await t.pumpAndSettle();
    expect(kinds, ['consumable', 'portable']);
  });

  testWidgets('use records quantity and optional person', (t) async {
    List<Rec>? written;
    await t.pumpWidget(MaterialApp(home: ItemPage(
      refs: refs, item: {'id': 3, 'name': 'Filament', 'kind': 'consumable'},
      loader: () async => ([{'item_id': 3, 'place_id': 1, 'qty': 10}], <Rec>[], <Rec>[], <Rec>[]),
      save: (rows) async { written = rows; },
    )));
    await t.pumpAndSettle();
    expect(find.text('Hand out'), findsNothing);
    expect(find.text('Take back'), findsNothing);
    await t.tap(find.text('Use'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '5');
    await choose(t, 'Person', 'Ana');
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(written, [expected('consume', from: 1, person: 2, qty: 5)]);
  });

  for (final take in [true, false]) {
    testWidgets('broken unit ${take ? 'takes a photo' : 'skips photo'}', (t) async {
      final asset = <String, dynamic>{'id': 4, 'item_id': 3, 'tag': 'GS-031'};
      Rec? photo;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => changeCondition(context, asset,
          update: (ids, change) async { expect(ids, [4]); expect(change, {'condition': 'broken'}); },
          pick: () async => (full: Uint8List.fromList([1, 2]), thumb: Uint8List.fromList([3, 4])),
          savePhoto: ({required itemId, assetId, required bytes, thumb, required state, note}) async {
            photo = {'item_id': itemId, 'asset_id': assetId, 'bytes': bytes, 'thumb': thumb, 'state': state};
          },
        ), child: const Text('Condition'),
      )))));
      await t.tap(find.text('Condition'));
      await t.pumpAndSettle();
      await t.tap(find.text('broken'));
      await t.pumpAndSettle();
      expect(find.text('Add a photo of its state?'), findsOneWidget);
      await t.tap(find.text(take ? 'Take photo' : 'Skip'));
      await t.pumpAndSettle();
      if (take) {
        expect(photo, {'item_id': 3, 'asset_id': 4, 'bytes': Uint8List.fromList([1, 2]), 'thumb': Uint8List.fromList([3, 4]), 'state': 'broken'});
      } else {
        expect(photo, isNull);
      }
    });
  }

  testWidgets('reference photo appears at the top', (t) async {
    await t.pumpWidget(MaterialApp(home: ItemPage(
      refs: refs, item: {'id': 3, 'name': 'Camera', 'kind': 'portable'},
      loader: () async => (<Rec>[], <Rec>[], <Rec>[], <Rec>[]),
      loadPhotos: (_) async => [{'path': 'reference.jpg', 'url': 'https://example.test/reference.jpg', 'thumb': 'https://example.test/reference.thumb.jpg', 'state': 'reference', 'taken_at': '2026-11-17T10:00:00Z'}],
    )));
    await t.pumpAndSettle();
    final large = t.widget<PhotoView>(find.byType(PhotoView).first);
    expect(large.large, isTrue);
    final image = t.widget<Image>(find.descendant(of: find.byWidget(large), matching: find.byType(Image)));
    expect((image.image as NetworkImage).url, 'https://example.test/reference.thumb.jpg');
    expect(large.photo['path'], 'reference.jpg');
    expect(find.text('No reference photo'), findsNothing);
  });

}
