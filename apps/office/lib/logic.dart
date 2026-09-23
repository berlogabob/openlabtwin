// Booking logic with no Flutter in it, so `flutter test` covers it.
// Times are the browser's local wall clock. ponytail: staff and lab are in Lisbon; store UTC, show local.

const kinds = ['class', 'consultation', 'club', 'workshop', 'equipment', 'maintenance', 'external'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

/// Weekly repeat until a date (inclusive), in the local form the export's dateutil expects (no Z).
String? weeklyRrule(DateTime? until) =>
    until == null ? null : 'FREQ=WEEKLY;UNTIL=${isoDate(until).replaceAll('-', '')}T235959';

DateTime? untilOf(String? rrule) {
  final m = RegExp(r'UNTIL=(\d{4})(\d{2})(\d{2})').firstMatch(rrule ?? '');
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

class Activity {
  Activity({
    this.id,
    this.title = '',
    this.layer = 'booking',
    this.kind = 'class',
    List<int>? placeIds,
    this.locationText = '',
    required this.start,
    required this.end,
    this.repeatUntil,
    List<String>? exdates,
    this.status = 'requested',
    this.requesterId,
    this.requesterDisplay = '',
    this.ownerStaffId,
    this.organizationId,
    this.attendees,
    this.purpose = '',
    this.publicNote = '',
  })  : placeIds = placeIds ?? [],
        exdates = exdates ?? [];

  factory Activity.fromRow(Map<String, dynamic> r) => Activity(
        id: r['id'] as int?,
        title: r['title'] as String,
        layer: r['layer'] as String,
        kind: r['kind'] as String,
        placeIds: [for (final p in r['place_ids'] as List) p as int],
        locationText: r['location_text'] as String? ?? '',
        start: DateTime.parse(r['starts_at'] as String).toLocal(),
        end: DateTime.parse(r['ends_at'] as String).toLocal(),
        repeatUntil: untilOf(r['rrule'] as String?),
        exdates: [for (final d in (r['exdates'] as List? ?? const [])) d as String],
        status: r['status'] as String,
        requesterId: r['requester_id'] as int?,
        requesterDisplay: r['requester_display'] as String? ?? '',
        ownerStaffId: r['owner_staff_id'] as int?,
        organizationId: r['organization_id'] as int?,
        attendees: r['attendees'] as int?,
        purpose: r['purpose'] as String? ?? '',
        publicNote: r['public_note'] as String? ?? '',
      );

  int? id, requesterId, ownerStaffId, organizationId, attendees;
  String title, layer, kind, locationText, status, requesterDisplay, purpose, publicNote;
  List<int> placeIds;
  List<String> exdates;
  DateTime start, end;
  DateTime? repeatUntil; // null = one-off

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'layer': layer,
        'kind': kind,
        'place_ids': placeIds,
        'location_text': _blank(locationText),
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': end.toUtc().toIso8601String(),
        'rrule': weeklyRrule(repeatUntil),
        'exdates': exdates,
        'status': status,
        'requester_id': requesterId,
        'requester_display': _blank(requesterDisplay),
        'owner_staff_id': ownerStaffId,
        'organization_id': organizationId,
        'attendees': attendees,
        'purpose': _blank(purpose),
        'public_note': _blank(publicNote),
      };

  /// Start of every occurrence: weekly until repeatUntil, minus the skipped dates.
  List<DateTime> occurrences() => repeatUntil == null
      ? [start]
      : [
          for (var d = start;
              !_day(d).isAfter(repeatUntil!);
              d = DateTime(d.year, d.month, d.day + 7, d.hour, d.minute))
            if (!exdates.contains(isoDate(d))) d
        ];

  String when() {
    final repeat = repeatUntil == null ? '' : ' · weekly until ${isoDate(repeatUntil!)}';
    return '${isoDate(start)} ${hhmm(start)}–${hhmm(end)}$repeat';
  }
}

int _min(String t) => int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));

/// Clash warnings for every occurrence of [a]: lessons in the same rooms (rows from `lessons`) and other
/// approved activities sharing a room. Warnings, not blocks: staff decide.
List<String> clashes(Activity a, Set<String> roomNames, List<Map<String, dynamic>> lessons, List<Activity> others) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final l in lessons) {
      final rooms = [for (final r in l['rooms'] as List) r as String].where(roomNames.contains);
      if (l['date'] == day && rooms.isNotEmpty && _min(l['start_time'] as String) < to && from < _min(l['end_time'] as String)) {
        out.add('$day ${(l['start_time'] as String).substring(0, 5)}–${(l['end_time'] as String).substring(0, 5)} '
            'lesson: ${l['course']} (${rooms.join(', ')})');
      }
    }
    for (final o in others) {
      if (o.id == a.id || !o.placeIds.any(a.placeIds.contains)) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} booking: ${o.title}');
        }
      }
    }
  }
  return out;
}
