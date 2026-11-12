import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/data.dart';
import 'package:office/report_screen.dart';

void main() {
  testWidgets('shows equipment request and outstanding summary', (tester) async {
    final refs = Refs([], [
      {'id': 1, 'name': 'Ana Silva', 'email': 'ana@example.org'},
    ], [], [
      {'id': 8, 'name': 'Camera'},
    ], [], null);
    Future<(List<Rec>, List<Rec>, List<Rec>)> loader(String from, String to) async => (
      [{'id': 2, 'title': 'Camera for class', 'kind': 'equipment', 'status': 'approved', 'starts_at': '${from}T10:00:00Z', 'requester_id': 1, 'requester_display': null}],
      [{'activity_id': 2, 'item_id': 8, 'qty': 1}],
      [{'activity_id': 2, 'kind': 'issue', 'qty': 1, 'item_id': 8}],
    );
    await tester.pumpWidget(MaterialApp(home: ReportScreen(refs: refs, loader: loader)));
    await tester.pumpAndSettle();
    expect(find.text('Camera for class'), findsOneWidget);
    expect(find.text('Ana Silva'), findsOneWidget);
    expect(find.text('1 requests, 1 outstanding'), findsOneWidget);
  });
}
