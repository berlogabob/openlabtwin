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

/// Normalise serials printed with or without separators.
String normaliseSerial(String serial) =>
    serial.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Extract a complete PS4 serial from an OCR result.
String? parsePs4Serial(String text) {
  final match = RegExp(r'(?:^|[^0-9])([0-9]{2}-?[0-9]{8}-?[0-9]{7})(?![0-9])')
      .firstMatch(text);
  return match == null ? null : normaliseSerial(match.group(1)!);
}

class Ps4Key {
  final String? product;
  final String unit;

  const Ps4Key({required this.product, required this.unit});
}

/// Extract the product (when present) and unit digits from PS4 scans.
Ps4Key? parsePs4Key(String raw) {
  final console = RegExp(
    r'(?:^|[^0-9])([0-9]{2})[-\s]?([0-9]{8})[-\s]?([0-9]{7})(?![0-9])',
  ).firstMatch(raw);
  if (console != null) {
    return Ps4Key(product: console.group(2), unit: console.group(3)!);
  }

  final unit = RegExp(r'(?:^|[^A-Za-z0-9])S[0-9]{2}-([0-9]{7})(?![0-9])')
      .firstMatch(raw);
  if (unit == null) return null;
  final product = RegExp(r'(?:^|[^A-Za-z0-9])P-([0-9]{8})(?![0-9])')
      .firstMatch(raw);
  return Ps4Key(product: product?.group(1), unit: unit.group(1)!);
}

bool _sameIdentity(String rawA, String rawB) {
  final a = parsePs4Key(rawA);
  final b = parsePs4Key(rawB);
  if (a != null && b != null) {
    return a.unit == b.unit &&
        (a.product == null || b.product == null || a.product == b.product);
  }
  return normaliseSerial(rawA) == normaliseSerial(rawB);
}

/// Match boxes against consoles.
///
/// Every serial is stripped of separators and upper-cased before comparison. Empty serials
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
  final List<String> boxRaw = <String>[];
  for (final String raw in boxSerials) {
    final String serial = normaliseSerial(raw);
    if (serial.isEmpty) continue;
    if (boxRaw.any((seen) => _sameIdentity(seen, raw))) continue;
    boxRaw.add(raw);
    boxes.add(serial);
  }

  final List<String> consoles = <String>[];
  final List<String> consoleRaw = <String>[];
  for (final String raw in consoleSerials) {
    final String serial = normaliseSerial(raw);
    if (serial.isEmpty) continue;
    if (consoleRaw.any((seen) => _sameIdentity(seen, raw))) continue;
    consoleRaw.add(raw);
    consoles.add(serial);
  }

  final List<String> duplicateBoxes = <String>[];
  final List<String> seenBoxes = <String>[];
  for (final String raw in boxSerials) {
    final String serial = normaliseSerial(raw);
    if (serial.isEmpty) continue;
    if (seenBoxes.any((seen) => _sameIdentity(seen, raw))) {
      if (!duplicateBoxes.contains(serial)) {
        duplicateBoxes.add(serial);
      }
    } else {
      seenBoxes.add(raw);
    }
  }

  final List<String> duplicateConsoles = <String>[];
  final List<String> seenConsoles = <String>[];
  for (final String raw in consoleSerials) {
    final String serial = normaliseSerial(raw);
    if (serial.isEmpty) continue;
    if (seenConsoles.any((seen) => _sameIdentity(seen, raw))) {
      if (!duplicateConsoles.contains(serial)) {
        duplicateConsoles.add(serial);
      }
    } else {
      seenConsoles.add(raw);
    }
  }

  final List<String> matched = <String>[];
  for (int i = 0; i < boxes.length; i++) {
    if (consoleRaw.any((console) => _sameIdentity(boxRaw[i], console))) {
      final String box = boxes[i];
      matched.add(box);
    }
  }

  final List<String> unmatchedBoxes = <String>[];
  for (int i = 0; i < boxes.length; i++) {
    if (!consoleRaw.any((console) => _sameIdentity(boxRaw[i], console))) {
      unmatchedBoxes.add(boxes[i]);
    }
  }

  final List<String> unmatchedConsoles = <String>[];
  for (int i = 0; i < consoles.length; i++) {
    if (!boxRaw.any((box) => _sameIdentity(box, consoleRaw[i]))) {
      unmatchedConsoles.add(consoles[i]);
    }
  }

  final int pairs = unmatchedBoxes.length < unmatchedConsoles.length
      ? unmatchedBoxes.length
      : unmatchedConsoles.length;
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

/// Export the pairing result as RFC 4180 CSV.
String pairingCsv(PairingResult r) {
  String cell(String value) => value.contains(RegExp('[",\r\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;
  final rows = <List<String>>[
    ['status', 'box_serial', 'console_serial'],
    for (final serial in r.matched) ['ok', serial, serial],
    for (final (box, console) in r.assignments) ['move', box, console],
    for (final box in r.leftoverBoxes) ['empty_box', box, ''],
    for (final console in r.leftoverConsoles) ['no_box', '', console],
  ];
  return '${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
}

/// Printable labels for consoles that need to move.
String stickerHtml(PairingResult r) {
  String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  return '''<!doctype html>
<html><head><meta charset="utf-8"><title>Console stickers</title>
<style>
@page { size: A4; margin: 10mm; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 3mm; }
.label { border: 1px solid #000; padding: 5mm; text-align: center; break-inside: avoid; overflow-wrap: anywhere; }
.serial { font: bold 24pt sans-serif; }
.box { font: 12pt sans-serif; }
</style></head><body><div class="grid">
${r.assignments.map((pair) => '<div class="label"><div class="serial">${escape(pair.$2)}</div><div class="box">Box ${escape(pair.$1)}</div></div>').join('\n')}
</div></body></html>''';
}
