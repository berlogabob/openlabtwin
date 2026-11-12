import 'pairing_logic.dart' show normaliseSerial;

enum ScanKind { place, asset, unknown }

class ScanResult {
  final ScanKind kind;
  final String code;
  final Map<String, dynamic>? row;
  const ScanResult(this.kind, this.code, [this.row]);
}

bool _same(String? value, String code) =>
    value != null && value.toLowerCase() == code.toLowerCase();

bool _sameSerial(String? value, String code) =>
    value != null &&
    normaliseSerial(code).isNotEmpty &&
    normaliseSerial(value) == normaliseSerial(code);

ScanResult resolveCode(
  String raw,
  List<Map<String, dynamic>> places,
  List<Map<String, dynamic>> assets,
) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return ScanResult(ScanKind.unknown, '');
  }

  String code = trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final place = uri.queryParameters['place'];
    if (place != null) {
      code = place;
      for (final p in places) {
        if (_same(p['code'] as String?, code)) {
          return ScanResult(ScanKind.place, code, p);
        }
      }
      return ScanResult(ScanKind.unknown, code);
    }
    final asset = uri.queryParameters['asset'];
    if (asset != null) {
      code = asset;
      for (final a in assets) {
        if (_same(a['tag'] as String?, code)) {
          return ScanResult(ScanKind.asset, code, a);
        }
        if (_sameSerial(a['serial'] as String?, code)) {
          return ScanResult(ScanKind.asset, code, a);
        }
      }
      return ScanResult(ScanKind.unknown, code);
    }
  }

  for (final p in places) {
    if (_same(p['code'] as String?, code)) {
      return ScanResult(ScanKind.place, code, p);
    }
  }
  for (final a in assets) {
    if (_same(a['tag'] as String?, code)) {
      return ScanResult(ScanKind.asset, code, a);
    }
    if (_sameSerial(a['serial'] as String?, code)) {
      return ScanResult(ScanKind.asset, code, a);
    }
  }

  return ScanResult(ScanKind.unknown, code);
}
