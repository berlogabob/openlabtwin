import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/bookings.dart';
import 'package:office/data.dart';
import 'package:office/storage_home.dart';
import 'package:office/storage_tools.dart';

void main() {
  final refs = Refs(
    [
      {'id': 1, 'name': 'Shelf', 'code': 'R15'},
    ],
    [
      {'id': 2, 'name': 'José'},
    ],
    [],
    [
      {'id': 3, 'name': 'Câmara', 'kind': 'portable'},
    ],
    [
      {'id': 4, 'item_id': 3, 'tag': 'TAG4', 'serial': 'SER4'},
    ],
    null,
  );
  Future<StorageRows> load() async => (
    [
      {'person_id': 2, 'item_id': 3, 'qty': 2},
    ],
    [
      {'person_id': 2, 'asset_id': 4},
    ],
    [
      {'code': 'missing', 'detail': 'Missing', 'key': 'missing'},
    ],
  );
  testWidgets('searches items, tags, places and people without accents', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StorageHome(refs: refs, loader: load),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    for (final (query, result) in [
      ('amar', 'Câmara'),
      ('TAG4', 'TAG4'),
      ('R15', 'R15 · Shelf'),
      ('jose', 'José'),
    ]) {
      await tester.enterText(field, query);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(ListTile), matching: find.text(result)),
        findsOneWidget,
      );
    }
  });
  testWidgets('shows loans, attention count and tools', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StorageHome(refs: refs, loader: load),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Out now'), findsOneWidget);
    expect(find.text('José · Câmara · TAG4'), findsOneWidget);
    expect(find.text('José · Câmara · 1'), findsOneWidget);
    expect(find.text('Needs attention (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.byType(StorageTools), findsOneWidget);
    for (final name in [
      'Record movement',
      'Needs attention',
      'Places',
      'Pair boxes and consoles',
      'Archive',
      'Usage',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });
  testWidgets('bookings app bar has only reload', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BookingsPage(refs: refs)));
    await tester.pump();
    expect(find.byTooltip('Reload'), findsOneWidget);
    expect(find.byTooltip('TV'), findsNothing);
    expect(find.byTooltip('Inventory'), findsNothing);
  });
  testWidgets('out now puts newest tagged units before untagged items', (
    tester,
  ) async {
    final r = Refs(
      [],
      [
        {'id': 2, 'name': 'Ana'},
      ],
      [],
      [
        {'id': 3, 'name': 'Zebra'},
        {'id': 6, 'name': 'Alpha'},
      ],
      [
        {'id': 4, 'item_id': 3, 'tag': 'OLD'},
        {'id': 5, 'item_id': 3, 'tag': 'NEW'},
      ],
      null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StorageHome(
          refs: r,
          loader: () async => (
            [
              {'person_id': 2, 'item_id': 3, 'qty': 3},
              {'person_id': 2, 'item_id': 6, 'qty': 1},
            ],
            [
              {'person_id': 2, 'asset_id': 4, 'at': '2026-01-01'},
              {'person_id': 2, 'asset_id': 5, 'at': '2026-11-01'},
            ],
            <Rec>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((x) => (x.title as Text?)?.data)
        .whereType<String>()
        .toList();
    expect(
      names.indexOf('Ana · Zebra · NEW'),
      lessThan(names.indexOf('Ana · Zebra · OLD')),
    );
    expect(
      names.indexOf('Ana · Zebra · OLD'),
      lessThan(names.indexOf('Ana · Alpha · 1')),
    );
    expect(
      names.indexOf('Ana · Alpha · 1'),
      lessThan(names.indexOf('Ana · Zebra · 1')),
    );
  });
}
