import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office/pairing_screen.dart';

void main() {
  testWidgets('pairs scanned boxes and consoles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingPage(camera: false)),
    );
    Future<void> scan(String code) async {
      await tester.enterText(find.byType(TextField), code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    for (final code in ['A', 'B', 'C']) {
      await scan(code);
    }
    await tester.ensureVisible(find.text('Done with boxes'));
    await tester.tap(find.text('Done with boxes'));
    await tester.pump();
    for (final code in ['A', 'C', 'D']) {
      await scan(code);
    }
    await tester.ensureVisible(find.text('Done with consoles'));
    await tester.tap(find.text('Done with consoles'));
    await tester.pump();
    expect(find.text('Put console D into box B'), findsOneWidget);
  });
}
