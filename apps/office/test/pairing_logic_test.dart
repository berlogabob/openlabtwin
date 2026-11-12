import 'package:office/pairing_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts complete PS4 serials from OCR text', () {
    expect(parsePs4Serial('Serial 03-27452573-6951476\n'), '03274525736951476');
    expect(parsePs4Serial('15274525959784902'), '15274525959784902');
    expect(parsePs4Serial('123456789012345678'), isNull);
    expect(parsePs4Serial('unreadable'), isNull);
  });
  test('parses PS4 product and unit keys from labels and OCR', () {
    expect(parsePs4Key('15-27452595-9784902')?.product, '27452595');
    expect(parsePs4Key(' 15274525959784902 ')?.unit, '9784902');
    expect(
      parsePs4Key('EU8 CUH-2216A B01W\n220-240V\nP-27452595-L\nS01-9784862-U')?.unit,
      '9784862',
    );
    expect(parsePs4Key('S01-9816817-0')?.product, isNull);
    expect(parsePs4Key('noise only'), isNull);
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
    test('PS4 boxes match consoles by unit and compatible product', () {
      final result = matchPairs(
        [
          'EU8 CUH-2216A B01W\n220-240V\nP-27452595-L\nS01-9784864-U',
          'P-27452595-L\nS01-9784902-U',
          'P-27452595-L\nS01-9784904-U',
          'P-27452595-L\nS01-9784888-U',
          'P-27452595-L\nS01-9784900-U',
          'P-27452595-L\nS01-9784924-U',
          'S01-9816817-0',
          'P-27452595-L\nS01-9784862-U',
          'P-27452595-L\nS01-9784899-U',
          'P-27452595-L\nS01-9784901-U',
          'P-27452595-L\nS01-9784876-U',
          'P-27452595-L\nS01-9784861-U',
          'P-27452595-L\nS01-9784903-U',
          'P-27452595-L\nS01-9784888-U',
          'P-27452595-L\nS01-9784902-U',
        ],
        [
          '15-27452595-9784863',
          '15-27452595-9784904',
          '15-27452595-9784902',
          '15-27452595-9784888',
          '15-27452595-9784886',
          '15-27452595-9816817',
          '15-27452595-9784864',
          '15-27452595-9784900',
          '15-27452595-9784923',
          '15-27452595-9784925',
          '15-27452595-9784924',
          '03-27452439-5893834',
          '03-27452573-6951476',
          '02-27452437-1812762',
          '15-27452595-9784902',
          '15-27452595-9784904',
          '15-27452595-9784888',
          '03-27452439-5893834',
          '15-27452595-9784863',
          '03-27452573-6951476',
          '15-27452595-9784886',
        ],
      );
      expect(result.matched, hasLength(7));
      expect(result.duplicateBoxes, hasLength(2));
      expect(result.duplicateConsoles, hasLength(7));
      expect(result.leftoverBoxes.length + result.assignments.length, 6);
      expect(result.leftoverBoxes, isEmpty);
      expect(result.assignments, hasLength(6));
      expect(result.leftoverConsoles, hasLength(1));
      expect(result.matched, hasLength(7));
    });
    test('different product does not match; unit-only box does', () {
      expect(
        matchPairs(['P-11111111-L\nS01-9784862-U'], ['15-27452595-9784862']).matched,
        isEmpty,
      );
      expect(
        matchPairs(['S01-9816817-0'], ['15-27452595-9816817']).matched,
        hasLength(1),
      );
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
