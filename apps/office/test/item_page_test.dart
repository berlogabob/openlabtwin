import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/data.dart';
import 'package:office/item_page.dart';
import 'package:office/scan_screen.dart';

void main() {
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
}
