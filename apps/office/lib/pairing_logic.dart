/// Pairing logic for lab office equipment.
///
/// A console box and the console it should hold carry the SAME serial.
library;

class PairingResult {
  final List<String> matched;
  final List<(String box, String console)> assignments;
  final List<String> leftoverBoxes;
  final List<String> leftoverConsoles;
  final List<String> duplicateBoxes;
  final List<String> duplicateConsoles;

  const PairingResult({
    required this.matched,
    required this.assignments,
    required this.leftoverBoxes,
    required this.leftoverConsoles,
    required this.duplicateBoxes,
    required this.duplicateConsoles,
  });
}

/// Normalise a raw serial: trim surrounding whitespace and upper-case it.
String _normalise(String serial) => serial.trim().toUpperCase();

/// Match boxes against consoles.
///
/// Every serial is trimmed and upper-cased before comparison. Empty serials
/// are dropped. A serial scanned twice in one list counts once (kept in first
/// scan order) and is listed in that side's duplicate list once.
///
/// `matched` holds serials present among both boxes and consoles, in box scan
/// order. Unmatched boxes and unmatched consoles are paired in scan order into
/// `(box, console)` assignments (a console placed into its box). If the counts
/// differ, the surplus becomes `leftoverBoxes` or `leftoverConsoles` in scan
/// order.
PairingResult matchPairs(List<String> boxSerials, List<String> consoleSerials) {
  final List<String> boxes = <String>[];
  final Set<String> boxSeen = <String>{};
  for (final String raw in boxSerials) {
    final String serial = _normalise(raw);
    if (serial.isEmpty) continue;
    if (boxSeen.contains(serial)) continue;
    boxSeen.add(serial);
    boxes.add(serial);
  }

  final List<String> consoles = <String>[];
  final Set<String> consoleSeen = <String>{};
  for (final String raw in consoleSerials) {
    final String serial = _normalise(raw);
    if (serial.isEmpty) continue;
    if (consoleSeen.contains(serial)) continue;
    consoleSeen.add(serial);
    consoles.add(serial);
  }

  final List<String> duplicateBoxes = <String>[];
  final Set<String> seenBoxes = <String>{};
  for (final String raw in boxSerials) {
    final String serial = _normalise(raw);
    if (serial.isEmpty) continue;
    if (!seenBoxes.add(serial)) {
      if (!duplicateBoxes.contains(serial)) {
        duplicateBoxes.add(serial);
      }
    }
  }

  final List<String> duplicateConsoles = <String>[];
  final Set<String> seenConsoles = <String>{};
  for (final String raw in consoleSerials) {
    final String serial = _normalise(raw);
    if (serial.isEmpty) continue;
    if (!seenConsoles.add(serial)) {
      if (!duplicateConsoles.contains(serial)) {
        duplicateConsoles.add(serial);
      }
    }
  }

  final List<String> matched = <String>[];
  for (final String box in boxes) {
    if (consoleSeen.contains(box)) {
      matched.add(box);
    }
  }

  final List<String> unmatchedBoxes = <String>[];
  for (final String box in boxes) {
    if (!consoleSeen.contains(box)) {
      unmatchedBoxes.add(box);
    }
  }

  final List<String> unmatchedConsoles = <String>[];
  for (final String console in consoles) {
    if (!boxSeen.contains(console)) {
      unmatchedConsoles.add(console);
    }
  }

  final int pairs = unmatchedBoxes.length < unmatchedConsoles.length ? unmatchedBoxes.length : unmatchedConsoles.length;
  final List<(String box, String console)> assignments = <(String, String)>[];
  for (int i = 0; i < pairs; i++) {
    assignments.add((unmatchedBoxes[i], unmatchedConsoles[i]));
  }

  final List<String> leftoverBoxes = <String>[];
  final List<String> leftoverConsoles = <String>[];
  for (int i = pairs; i < unmatchedBoxes.length; i++) {
    leftoverBoxes.add(unmatchedBoxes[i]);
  }
  for (int i = pairs; i < unmatchedConsoles.length; i++) {
    leftoverConsoles.add(unmatchedConsoles[i]);
  }

  return PairingResult(
    matched: matched,
    assignments: assignments,
    leftoverBoxes: leftoverBoxes,
    leftoverConsoles: leftoverConsoles,
    duplicateBoxes: duplicateBoxes,
    duplicateConsoles: duplicateConsoles,
  );
}
