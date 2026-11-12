const List<String> reportColumns = [
  'id',
  'date',
  'title',
  'requester',
  'email',
  'status',
  'items',
  'issued',
  'returned',
  'outstanding',
  'state',
];

String _num(num n) {
  final d = n.toDouble();
  if (d.isFinite && d == d.roundToDouble()) {
    return d.round().toString();
  }
  return n.toString();
}

List<Map<String, dynamic>> bookingReport({
  required List<Map<String, dynamic>> activities,
  required List<Map<String, dynamic>> lines,
  required List<Map<String, dynamic>> movements,
  required List<Map<String, dynamic>> people,
  required Map<int, String> itemNames,
  required String from,
  required String to,
}) {
  final peopleById = {for (final p in people) p['id']: p};

  final linesByActivity = <int, List<Map<String, dynamic>>>{};
  for (final l in lines) {
    (linesByActivity[l['activity_id']] ??= []).add(l);
  }
  for (final group in linesByActivity.values) {
    group.sort((a, b) => (a['item_id'] as int).compareTo(b['item_id'] as int));
  }

  final issuedByActivity = <int, num>{};
  final returnedByActivity = <int, num>{};
  for (final m in movements) {
    final aid = m['activity_id'] as int;
    if (m['kind'] == 'issue') {
      issuedByActivity[aid] = (issuedByActivity[aid] ?? 0) + (m['qty'] as num);
    } else if (m['kind'] == 'return') {
      returnedByActivity[aid] =
          (returnedByActivity[aid] ?? 0) + (m['qty'] as num);
    }
  }

  final rows = <Map<String, dynamic>>[];
  for (final a in activities) {
    if (a['kind'] != 'equipment') continue;
    final date = (a['starts_at'] as String).substring(0, 10);
    if (date.compareTo(from) < 0 || date.compareTo(to) > 0) continue;
    rows.add(a);
  }
  rows.sort((a, b) {
    final byStart = (a['starts_at'] as String).compareTo(
      b['starts_at'] as String,
    );
    if (byStart != 0) return byStart;
    return (a['id'] as int).compareTo(b['id'] as int);
  });

  final out = <Map<String, dynamic>>[];
  for (final a in rows) {
    final id = a['id'] as int;
    final requesterId = a['requester_id'] as int?;
    final person = requesterId != null ? peopleById[requesterId] : null;
    final requester =
        (person?['name'] as String? ?? a['requester_display'] as String? ?? '')
            .toString();
    final email = person?['email'] as String? ?? '';

    final group = linesByActivity[id] ?? <Map<String, dynamic>>[];
    final items = [
      for (final l in group)
        '${itemNames[l['item_id']] ?? 'item ${l['item_id']}'} x${_num(l['qty'] as num)}',
    ].join('; ');

    final issued = issuedByActivity[id] ?? 0;
    final returned = returnedByActivity[id] ?? 0;
    final outstanding = (issued - returned) < 0 ? 0 : issued - returned;
    final state = issued == 0
        ? 'not issued'
        : (outstanding == 0 ? 'returned' : 'outstanding');

    out.add({
      'id': id,
      'date': (a['starts_at'] as String).substring(0, 10),
      'title': a['title'] as String,
      'requester': requester,
      'email': email,
      'status': a['status'] as String,
      'items': items,
      'issued': issued,
      'returned': returned,
      'outstanding': outstanding,
      'state': state,
    });
  }
  return out;
}

String reportCsv(List<Map<String, dynamic>> rows) {
  String field(dynamic v) {
    final s = v == null ? '' : v.toString();
    if (s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  final buffer = StringBuffer();
  buffer.write(reportColumns.join(','));
  buffer.write('\n');
  for (final row in rows) {
    buffer.write([for (final c in reportColumns) field(row[c])].join(','));
    buffer.write('\n');
  }
  return buffer.toString();
}
