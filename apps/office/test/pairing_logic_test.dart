import 'package:office/pairing_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchPairs', () {
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
      expect(result.assignments, <(String, String)>[('B1', 'C1'), ('B2', 'C2')]);
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
      final result = matchPairs(['b1', ' B1 ', 'b2', 'b2', 'b3'], ['B1', 'c1', 'C1']);
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
}
