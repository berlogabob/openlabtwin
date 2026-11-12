import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/scan_widget.dart';

void main() {
  testWidgets('submits trimmed text and ignores empty input', (tester) async {
    final codes = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CodeCapture(camera: false, onCode: codes.add))));

    final field = find.byType(TextField);
    await tester.enterText(field, '  ABC-123  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(codes, ['ABC-123']);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(codes, ['ABC-123']);
  });
}
