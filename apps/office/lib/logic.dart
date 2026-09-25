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
    this.contactLink = '',
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
        contactLink: r['contact_link'] as String? ?? '',
      );

  int? id, requesterId, ownerStaffId, organizationId, attendees;
  String title, layer, kind, locationText, status, requesterDisplay, purpose, publicNote;
  final String contactLink; // from the "Book me" form; read-only here, so toRow() leaves it alone
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

// ---------- inventory ----------

const movementKinds = ['receive', 'move', 'issue', 'return', 'consume', 'adjust'];

/// A `movements` row, checked against the same shape rule the database enforces (movement_shape).
/// Fields a kind doesn't use are sent as null, so the check constraint never trips on leftovers.
Map<String, dynamic> movementRow({
  required String kind,
  required int itemId,
  required num qty,
  int? from,
  int? to,
  int? personId,
  int? activityId,
  int? byStaff,
}) {
  var problem = switch (kind) {
    'receive' => to == null ? 'Pick where it goes.' : null,
    'move' => from == null || to == null ? 'Pick both places.' : (from == to ? 'From and to must differ.' : null),
    'issue' => from == null || personId == null ? 'Pick the place and the person.' : null,
    'return' => to == null || personId == null ? 'Pick the person and where it goes back.' : null,
    'consume' => from == null ? 'Pick where it was used from.' : null,
    'adjust' => to == null ? 'Pick the place to correct.' : null,
    _ => 'Unknown kind: $kind',
  };
  if (problem == null && kind == 'adjust' && qty == 0) problem = 'A correction of 0 changes nothing.';
  if (problem == null && kind != 'adjust' && qty <= 0) problem = 'Quantity must be more than 0.';
  if (problem != null) throw ArgumentError(problem);
  return {
    'kind': kind,
    'item_id': itemId,
    'qty': qty,
    'from_place': const {'move', 'issue', 'consume'}.contains(kind) ? from : null,
    'to_place': const {'receive', 'move', 'return', 'adjust'}.contains(kind) ? to : null,
    'person_id': const {'issue', 'return'}.contains(kind) ? personId : null,
    'activity_id': activityId,
    'by_staff': byStaff,
  };
}

/// Kit lines (item_id, qty) the place can't cover, as readable warnings. Stock rows: item_id, place_id, qty.
List<String> shortages(List<Map<String, dynamic>> kit, int placeId, List<Map<String, dynamic>> stock, Map<int, String> names) {
  num have(int item) => stock.where((s) => s['item_id'] == item && s['place_id'] == placeId).fold<num>(0, (t, s) => t + (s['qty'] as num));
  return [
    for (final k in kit)
      if (have(k['item_id'] as int) < (k['qty'] as num))
        '${names[k['item_id']] ?? 'item ${k['item_id']}'}: need ${k['qty']}, have ${have(k['item_id'] as int)}'
  ];
}

/// Stationary items (laser cutter, 3D printer…) that another approved activity has at an overlapping time.
List<String> equipmentClashes(Activity a, Set<int> mine, List<(Activity, Set<int>)> others, Map<int, String> names) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final day = isoDate(s), from = _min(hhmm(s)), to = _min(hhmm(s.add(length)));
    for (final (o, theirs) in others) {
      final shared = mine.intersection(theirs);
      if (o.id == a.id || shared.isEmpty) continue;
      final oLength = o.end.difference(o.start);
      for (final os in o.occurrences()) {
        if (isoDate(os) == day && _min(hhmm(os)) < to && from < _min(hhmm(os.add(oLength)))) {
          out.add('$day ${hhmm(os)}–${hhmm(os.add(oLength))} ${[for (final i in shared) names[i] ?? '$i'].join(', ')} '
              'also booked for ${o.title}');
        }
      }
    }
  }
  return out;
}

/// A TV carousel slide (tv_slides). The node applies the same date rule when it builds the playlist.
class TvSlide {
  TvSlide({
    this.id,
    this.kind = 'media',
    this.title = '',
    this.body = '',
    this.mediaName,
    this.url = '',
    this.seconds = 10,
    this.position = 0,
    this.startsOn,
    this.endsOn,
    this.active = true,
    this.fromTime,
    this.toTime,
    this.fullscreen = false,
    this.takeover = false,
  });

  factory TvSlide.fromRow(Map<String, dynamic> r) => TvSlide(
        id: r['id'] as int?,
        kind: r['kind'] as String,
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        mediaName: r['media_name'] as String?,
        url: r['url'] as String? ?? '',
        seconds: r['seconds'] as int?,
        position: r['position'] as int? ?? 0,
        startsOn: r['starts_on'] == null ? null : DateTime.parse(r['starts_on'] as String),
        endsOn: r['ends_on'] == null ? null : DateTime.parse(r['ends_on'] as String),
        active: r['active'] as bool? ?? true,
        fromTime: (r['from_time'] as String?)?.substring(0, 5),
        toTime: (r['to_time'] as String?)?.substring(0, 5),
        fullscreen: r['fullscreen'] as bool? ?? false,
        takeover: r['takeover'] as bool? ?? false,
      );

  int? id;
  String kind, title, body, url;
  String? fromTime, toTime; // HH:MM, times of day the page plays; null: all day
  bool fullscreen, takeover; // takeover: while on, the TV plays only takeover pages
  String? mediaName;
  int? seconds; // null: play the video to its end
  int position;
  DateTime? startsOn, endsOn;
  bool active;

  Map<String, dynamic> toRow() => {
        'kind': kind,
        'title': _blank(title),
        'body': _blank(body),
        'media_name': mediaName,
        'url': _blank(url),
        'seconds': seconds,
        'position': position,
        'starts_on': startsOn == null ? null : isoDate(startsOn!),
        'ends_on': endsOn == null ? null : isoDate(endsOn!),
        'active': active,
        'from_time': fromTime,
        'to_time': toTime,
        'fullscreen': fullscreen,
        'takeover': takeover,
      };

  bool showsOn(DateTime day) {
    final d = isoDate(day);
    return active &&
        (startsOn == null || isoDate(startsOn!).compareTo(d) <= 0) &&
        (endsOn == null || isoDate(endsOn!).compareTo(d) >= 0);
  }

  /// The first thing to fix before saving, or null.
  String? problem() {
    if (kind == 'media' && mediaName == null) return 'Pick a file.';
    if ((kind == 'bio' || kind == 'text') && title.trim().isEmpty) {
      return kind == 'bio' ? 'Add a name.' : 'Add a title.';
    }
    if (kind == 'qr' && !RegExp(r'^https?://\S+$').hasMatch(url.trim())) {
      return 'The link must start with http:// or https://.';
    }
    if (seconds != null && seconds! < 1) return 'Seconds must be at least 1.';
    if (fromTime != null && toTime != null && toTime!.compareTo(fromTime!) <= 0) {
      return 'The end time is before the start time.';
    }
    if (startsOn != null && endsOn != null && endsOn!.isBefore(startsOn!)) {
      return 'The end date is before the start date.';
    }
    return null;
  }
}

/// The office's line about the TV, from the node's heartbeat (tv_status): what it plays, or why it is stale.
/// ok is false when the last build is more than 5 minutes old, never happened, or the last run failed.
({String text, bool ok}) tvStatusLine(Map<String, dynamic>? r, DateTime now) {
  String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final built = r?['built_at'] == null ? null : DateTime.parse(r!['built_at'] as String).toLocal();
  final errorAt = r?['error_at'] == null ? null : DateTime.parse(r!['error_at'] as String).toLocal();
  if (built == null) return (text: 'TV: the lab node has not built a playlist yet.${r?['error'] == null ? '' : ' ${r!['error']}'}', ok: false);
  final failing = errorAt != null && errorAt.isAfter(built);
  if (failing || now.difference(built).inMinutes >= 5) {
    return (text: 'TV not updating since ${hm(built)}${failing ? ': ${r!['error']}' : ': is the lab node on?'}', ok: false);
  }
  return (
    text: 'TV playlist built ${hm(built)} · ${r!['pages']} pages · ${r['media']} files${r['takeover'] == true ? ' · takeover on' : ''}',
    ok: true,
  );
}
