import 'package:office/pairing_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts complete PS4 serials from OCR text', () {
    expect(parsePs4Serial('Serial 03-27452573-6951476\n'), '03274525736951476');
    expect(parsePs4Serial('15274525959784902'), '15274525959784902');
    expect(parsePs4Serial('123456789012345678'), isNull);
    expect(parsePs4Serial('unreadable'), isNull);
  });
  group('matchPairs', () {
    test('serial separators do not affect matching or duplicates', () {
      final result = matchPairs(
        ['15-27452595-9784902', '15 27452595 9784902'],
        ['15274525959784902'],
      );
      expect(result.matched, ['15274525959784902']);
      expect(result.duplicateBoxes, ['15274525959784902']);
      expect(normaliseSerial(' a-b.12 '), 'AB12');
    });
    test('all matched', () {
      final result = matchPairs(['A', 'B', 'C'], ['A', 'B', 'C']);
      expect(result.matched, ['A', 'B', 'C']);
      expect(result.assignments, isEmpty);
      expect(result.leftoverBoxes, isEmpty);
      expect(result.leftoverConsoles, isEmpty);
    });
    test('two swapped', () {
      final result = matchPairs(['A', 'B', 'C'], ['A', 'C', 'D']);
      expect(result.matched, ['A', 'C']);
      expect(result.assignments, <(String, String)>[('B', 'D')]);
      expect(result.leftoverBoxes, isEmpty);
      expect(result.leftoverConsoles, isEmpty);
    });
    test('more consoles than boxes', () {
      final result = matchPairs(['B1', 'B2'], ['C1', 'C2', 'C3', 'C4']);
      expect(result.matched, isEmpty);
      expect(result.assignments, <(String, String)>[
        ('B1', 'C1'),
        ('B2', 'C2'),
      ]);
      expect(result.leftoverBoxes, isEmpty);
      expect(result.leftoverConsoles, ['C3', 'C4']);
    });
    test('more boxes than consoles', () {
      final result = matchPairs(['B1', 'B2', 'B3'], ['C1']);
      expect(result.matched, isEmpty);
      expect(result.assignments, <(String, String)>[('B1', 'C1')]);
      expect(result.leftoverBoxes, ['B2', 'B3']);
      expect(result.leftoverConsoles, isEmpty);
    });
    test('duplicates and lowercase/whitespace', () {
      final result = matchPairs(
        ['b1', ' B1 ', 'b2', 'b2', 'b3'],
        ['B1', 'c1', 'C1'],
      );
      expect(result.matched, ['B1']);
      expect(result.duplicateBoxes, ['B1', 'B2']);
      expect(result.duplicateConsoles, ['C1']);
      expect(result.assignments, <(String, String)>[('B2', 'C1')]);
      expect(result.leftoverBoxes, ['B3']);
      expect(result.leftoverConsoles, isEmpty);
    });
    test('empty lists', () {
      final result = matchPairs(const [], const []);
      expect(result.matched, isEmpty);
      expect(result.assignments, isEmpty);
      expect(result.leftoverBoxes, isEmpty);
      expect(result.leftoverConsoles, isEmpty);
      expect(result.duplicateBoxes, isEmpty);
      expect(result.duplicateConsoles, isEmpty);
    });
  });
  test('CSV includes all statuses and quotes special characters', () {
    final result = PairingResult(
      matched: ['A'],
      assignments: [('B,"x"', 'C\nD')],
      leftoverBoxes: ['E'],
      leftoverConsoles: ['F'],
      duplicateBoxes: [],
      duplicateConsoles: [],
    );
    expect(
      pairingCsv(result),
      'status,box_serial,console_serial\r\nok,A,A\r\nmove,"B,""x""","C\nD"\r\nempty_box,E,\r\nno_box,,F\r\n',
    );
  });
  test('stickers escape serials and only include assignments', () {
    final result = PairingResult(
      matched: ['MATCHED'],
      assignments: [('<box & "x">', "console & <'x'>")],
      leftoverBoxes: [],
      leftoverConsoles: [],
      duplicateBoxes: [],
      duplicateConsoles: [],
    );
    final html = stickerHtml(result);
    expect(html, contains('@page { size: A4'));
    expect(html, contains('Box &lt;box &amp; &quot;x&quot;&gt;'));
    expect(html, contains('console &amp; &lt;&#39;x&#39;&gt;'));
    expect(html, isNot(contains('MATCHED')));
  });
}
