import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/data.dart';
import 'package:office/scan_screen.dart';

void main() {
  final refs = Refs(
    [
      {'id': 1, 'name': 'Camera shelf', 'code': 'S1'},
    ],
    [
      {'id': 2, 'name': 'Alex'},
    ],
    [],
    [
      {'id': 3, 'name': 'Camera'},
    ],
    [],
    null,
  );

  testWidgets('unknown code offers matching items and places', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ScanPage(refs: refs, camera: false)),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Type or scan with a USB scanner'),
      'camera',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Not in the catalogue: camera'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('S1 · Camera shelf'), findsOneWidget);
    expect(find.textContaining('To add it:'), findsOneWidget);
  });

  testWidgets('asset shows who holds it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetPage(
          refs: refs,
          asset: {'id': 4, 'item_id': 3, 'tag': 'A4'},
          loadPlaces: () async => [
            {'asset_id': 4, 'person_id': 2},
          ],
          loadHistory: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Held by Alex'), findsOneWidget);
    expect(find.text('Item: Camera'), findsOneWidget);
  });
}
