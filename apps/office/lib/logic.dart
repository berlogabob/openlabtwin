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

bool isGone(int itemId, List<Map<String, dynamic>> stock, List<Map<String, dynamic>> loans) =>
    stock.where((s) => s['item_id'] == itemId).fold<num>(0, (total, s) => total + (s['qty'] as num)) == 0 &&
    !loans.any((l) => l['item_id'] == itemId && (l['qty'] as num) > 0);

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
  int? assetId,
  String? note,
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
  if (problem == null && assetId != null && qty.abs() != 1) problem = 'A tagged item moves one at a time (quantity 1).';
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
    'asset_id': assetId,
    'note': note,
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
    this.every,
    this.activityId,
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
        every: r['every_seconds'] as int?,
        activityId: r['activity_id'] as int?,
      );

  int? id;
  String kind, title, body, url;
  String? fromTime, toTime; // HH:MM, times of day the page plays; null: all day
  bool fullscreen, takeover; // takeover: while on, the TV plays only takeover pages
  int? every; // announcement: out of the loop, shown every this many seconds for its own seconds
  int? activityId; // linked schedule event: the page plays in its time slot, its own dates and times are ignored
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
        'every_seconds': every,
        'activity_id': activityId,
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
    if (every != null && every! <= (seconds ?? 0)) {
      return 'Show every: the gap must be longer than the page\'s seconds (a whole video needs its seconds set).';
    }
    if (takeover && activityId == null && endsOn == null && toTime == null) {
      return 'A takeover needs an end: set "Until" (a date or a time), or it takes over the TV for good.';
    }
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
    text: '${r!['playing'] ?? 'TV playlist built'} · built ${hm(built)} · ${r['media']} files',
    ok: true,
  );
}

/// Warnings per slide id, for the office list: takeover pages whose dates and times overlap, and pages that use the same file.
/// (Drafted by a local model, Qwen3-Coder on Unsloth Studio, then corrected.)
Map<int, String> tvWarnings(List<TvSlide> slides) {
  final on = [for (final s in slides) if (s.active && s.id != null) s];
  String name(TvSlide s) => s.title.isNotEmpty ? s.title : s.mediaName ?? s.kind;
  String day(DateTime? d, String open) => d == null ? open : isoDate(d);
  bool overlap(TvSlide a, TvSlide b) =>
      a.takeover &&
      b.takeover &&
      day(a.startsOn, '0000-01-01').compareTo(day(b.endsOn, '9999-12-31')) <= 0 &&
      day(b.startsOn, '0000-01-01').compareTo(day(a.endsOn, '9999-12-31')) <= 0 &&
      (a.fromTime ?? '00:00').compareTo(b.toTime ?? '24:00') < 0 &&
      (b.fromTime ?? '00:00').compareTo(a.toTime ?? '24:00') < 0;
  return {
    for (final s in on)
      if ([
        for (final o in on) if (o != s && overlap(s, o)) 'overlaps takeover "${name(o)}"',
        for (final o in on) if (o != s && s.mediaName != null && o.mediaName == s.mediaName) 'same file as "${name(o)}"',
      ] case final m when m.isNotEmpty)
        s.id!: m.join('; '),
  };
}

// ---------- smart storage ----------

final _code = RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$');

/// Place codes are capitals, digits and dashes (R15-L-S3): the database's check, before the round trip.
bool validCode(String code) => _code.hasMatch(code);

/// Places parents first, each with its depth; siblings by code, then name. A place whose parent is missing is a root.
List<(Map<String, dynamic>, int)> placeTree(List<Map<String, dynamic>> places) {
  final ids = {for (final p in places) p['id']};
  final kids = <Object?, List<Map<String, dynamic>>>{};
  for (final p in places) {
    kids.putIfAbsent(ids.contains(p['parent_id']) ? p['parent_id'] : null, () => []).add(p);
  }
  String key(Map<String, dynamic> p) => '${p['code'] ?? '~'} ${p['name']}';
  final out = <(Map<String, dynamic>, int)>[];
  final seen = <Object?>{};
  void walk(Object? parent, int depth) {
    for (final p in (kids[parent] ?? <Map<String, dynamic>>[])..sort((a, b) => key(a).compareTo(key(b)))) {
      if (!seen.add(p['id'])) continue;
      out.add((p, depth));
      walk(p['id'], depth + 1);
    }
  }

  walk(null, 0);
  // a parent loop: show those places at the top rather than lose them
  out.addAll([for (final p in places) if (!seen.contains(p['id'])) (p, 0)]);
  return out;
}

/// Stocktake: one 'adjust' row per counted item whose count differs from what the place should hold.
/// expected and counted map item id -> quantity (untagged only; tagged items are ticked one by one).
List<Map<String, dynamic>> countAdjustments(Map<int, num> expected, Map<int, num> counted, int placeId, {int? byStaff}) => [
      for (final e in counted.entries)
        if (e.value != (expected[e.key] ?? 0))
          movementRow(kind: 'adjust', itemId: e.key, qty: e.value - (expected[e.key] ?? 0), to: placeId, byStaff: byStaff, note: 'stocktake')
    ];

/// Tagging one unit here: the tag's receive, plus an untagged −1 only when an untagged one was recorded here.
/// Otherwise the unit was never recorded, and the receive alone adds it.
List<Map<String, dynamic>> tagRows(int itemId, int assetId, int placeId, num untaggedHere, {int? byStaff}) => [
      movementRow(kind: 'receive', itemId: itemId, qty: 1, to: placeId, assetId: assetId, byStaff: byStaff, note: 'tagged'),
      if (untaggedHere > 0) movementRow(kind: 'adjust', itemId: itemId, qty: -1, to: placeId, byStaff: byStaff, note: 'tagged'),
    ];

/// A booking's kit, tagged units first: an issue takes the tags on that shelf, a return brings back the tags the person holds;
/// untagged units make up the rest. assets: id, item_id, tag. where (asset_place): asset_id, place_id, person_id.
/// Returns the rows and the picked tags, to show before anything is written.
(List<Map<String, dynamic>>, List<String>) kitRows(String kind, List<Map<String, dynamic>> kit, int? placeId, int? personId,
    List<Map<String, dynamic>> assets, List<Map<String, dynamic>> where,
    {int? activityId, int? byStaff}) {
  final pool = {
    for (final w in where)
      if (kind == 'issue' ? placeId != null && w['place_id'] == placeId : personId != null && w['person_id'] == personId) w['asset_id']
  };
  final rows = <Map<String, dynamic>>[];
  final picked = <String>[];
  for (final k in kit) {
    final item = k['item_id'] as int;
    var left = k['qty'] as num;
    for (final a in assets) {
      if (left < 1) break;
      if (a['item_id'] != item || !pool.remove(a['id'])) continue;
      left -= 1;
      picked.add(a['tag'] as String);
      rows.add(movementRow(
          kind: kind, itemId: item, qty: 1, from: placeId, to: placeId, personId: personId, activityId: activityId, byStaff: byStaff, assetId: a['id'] as int));
    }
    if (left > 0) {
      rows.add(movementRow(kind: kind, itemId: item, qty: left, from: placeId, to: placeId, personId: personId, activityId: activityId, byStaff: byStaff));
    }
  }
  return (rows, picked);
}

/// Stocktake "found here": a tagged unit seen here but recorded elsewhere comes here. A move from its place, a return from whoever
/// holds it, or a receive if it was nowhere. Nothing when it is already here. where: its asset_place row, or null.
List<Map<String, dynamic>> foundRows(Map<String, dynamic> asset, Map<String, dynamic>? where, int placeId, {int? byStaff}) {
  final from = where?['place_id'] as int?, person = where?['person_id'] as int?;
  if (from == placeId) return [];
  return [
    movementRow(
        kind: from != null ? 'move' : (person != null ? 'return' : 'receive'),
        itemId: asset['item_id'] as int,
        qty: 1,
        from: from,
        to: placeId,
        personId: person,
        assetId: asset['id'] as int,
        byStaff: byStaff,
        note: 'stocktake')
  ];
}

/// Portable equipment asked for more than the lab owns: at each session of this booking, its kit plus every overlapping
/// approved booking's kit, against the lab's total stock. others: (booking, item id -> qty). totals: item id -> units owned.
List<String> demandWarnings(
    Activity a, Map<int, num> mine, List<(Activity, Map<int, num>)> others, Map<int, num> totals, Map<int, String> names) {
  final out = <String>[];
  final length = a.end.difference(a.start);
  for (final s in a.occurrences()) {
    final e = s.add(length);
    for (final item in mine.keys) {
      var need = mine[item]!;
      final who = <String>[];
      for (final (o, kit) in others) {
        final q = kit[item];
        if (q == null || o.id == a.id) continue;
        final oLength = o.end.difference(o.start);
        if (o.occurrences().any((os) => os.isBefore(e) && s.isBefore(os.add(oLength)))) {
          need += q;
          who.add('${o.title} $q');
        }
      }
      final have = totals[item] ?? 0;
      if (who.isNotEmpty && need > have) {
        out.add('${isoDate(s)} ${hhmm(s)}: ${names[item] ?? 'item $item'} needed $need (this ${mine[item]}, ${who.join(', ')}), '
            'the lab has $have');
      }
    }
  }
  return out;
}

/// Matches an extracted student number first, then the extracted name.
int? personFor(Map extracted, List<Map<String, dynamic>> people) {
  final number = extracted['student_number']?.toString().trim();
  if (number != null && number.isNotEmpty) {
    for (final p in people) {
      if (p['student_number']?.toString() == number) return p['id'] as int;
    }
  }
  final name = extracted['name']?.toString().trim().toLowerCase();
  if (name == null || name.isEmpty) return null;
  for (final p in people) {
    if (p['name']?.toString().trim().toLowerCase() == name) return p['id'] as int;
  }
  return null;
}

/// Converts edited sheet lines to the JSON shape accepted by approve_sheet.
List<Map<String, dynamic>> sheetLoans({required int? personId, String? course, String? outOn, String? backOn, required List<Map<String, dynamic>> lines}) {
  final out = _archiveDate(outOn, 'Out on');
  final back = _archiveDate(backOn, 'Back on');
  if (out != null && back != null && back.compareTo(out) < 0) throw ArgumentError('Back on must not be before out on.');
  return [
    for (final line in lines)
      if (line['item_text']?.toString().trim().isNotEmpty == true)
        {
          'person_id': personId,
          'course': course?.trim(),
          'item_id': line['item_id'],
          'item_text': line['item_text'].toString().trim(),
          'qty': _quantity(line['qty']),
          'out_on': out,
          'back_on': back,
        },
  ];
}

num _quantity(Object? value) {
  final n = value is num ? value : num.tryParse('$value') ?? 1;
  return n < 1 ? 1 : n;
}

String? _archiveDate(String? value, String label) {
  final s = value?.trim() ?? '';
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) || isoDate(parsed) != s) {
    throw ArgumentError('$label must be a real date in YYYY-MM-DD format.');
  }
  return s;
}

/// Totals usage by item, retaining archive and live units separately.
List<({String name, num units, num archive, num live})> topItems(List<Map<String, dynamic>> usageRows, {int n = 10}) {
  final totals = <String, ({num units, num archive, num live})>{};
  for (final row in usageRows) {
    final name = row['name'].toString(), units = row['units'] as num;
    final old = totals[name] ?? (units: 0, archive: 0, live: 0);
    totals[name] = (units: old.units + units, archive: old.archive + (row['source'] == 'archive' ? units : 0), live: old.live + (row['source'] == 'live' ? units : 0));
  }
  final rows = [for (final e in totals.entries) (name: e.key, units: e.value.units, archive: e.value.archive, live: e.value.live)];
  rows.sort((a, b) => b.units == a.units ? a.name.compareTo(b.name) : b.units.compareTo(a.units));
  return rows.take(n < 0 ? 0 : n).toList();
}

/// Returns items whose recorded peak reached the current owned quantity.
List<Map<String, dynamic>> buyList(List<Map<String, dynamic>> peaks) => [...peaks.where((r) => (r['peak'] as num) >= (r['owned'] as num))]
  ..sort((a, b) {
    final left = (a['peak'] as num) - (a['owned'] as num);
    final right = (b['peak'] as num) - (b['owned'] as num);
    return right == left ? a['name'].toString().compareTo(b['name'].toString()) : right.compareTo(left);
  });

/// A video wall playlist entry (wall_slides). Same schedule fields as TvSlide; the wall server applies the TV's rules.
class WallSlide {
  WallSlide({
    this.id,
    this.mode = 'videowall',
    this.title = '',
    List<String>? mediaNames,
    this.seconds,
    this.cycleSeconds,
    this.fit = 'fit',
    this.showTitle = false,
    this.credits = '',
    this.logo = false,
    this.matte = 0,
    this.position = 0,
    this.active = true,
    this.startsOn,
    this.endsOn,
    this.fromTime,
    this.toTime,
    this.takeover = false,
    this.every,
    this.activityId,
  }) : mediaNames = mediaNames ?? [];

  factory WallSlide.fromRow(Map<String, dynamic> r) => WallSlide(
        id: r['id'] as int?,
        mode: r['mode'] as String,
        title: r['title'] as String? ?? '',
        mediaNames: [for (final n in (r['media_names'] as List? ?? const [])) n as String],
        seconds: r['seconds'] as int?,
        cycleSeconds: r['cycle_seconds'] as int?,
        fit: r['fit'] as String? ?? 'fit',
        showTitle: r['show_title'] as bool? ?? false,
        credits: r['credits'] as String? ?? '',
        logo: r['logo'] as bool? ?? false,
        matte: r['matte'] as int? ?? 0,
        position: r['position'] as int? ?? 0,
        active: r['active'] as bool? ?? true,
        startsOn: r['starts_on'] == null ? null : DateTime.parse(r['starts_on'] as String),
        endsOn: r['ends_on'] == null ? null : DateTime.parse(r['ends_on'] as String),
        fromTime: (r['from_time'] as String?)?.substring(0, 5),
        toTime: (r['to_time'] as String?)?.substring(0, 5),
        takeover: r['takeover'] as bool? ?? false,
        every: r['every_seconds'] as int?,
        activityId: r['activity_id'] as int?,
      );

  int? id;
  String mode; // 'mosaic' (one file per screen) or 'videowall' (one picture over all screens)
  String title, fit, credits; // fit: fit (bars), fill (cut), center (no scaling)
  List<String> mediaNames; // videowall: exactly one; mosaic: empty = every file in the folder
  int? seconds, cycleSeconds, every, activityId;
  bool showTitle, logo, active, takeover;
  int matte, position;
  DateTime? startsOn, endsOn;
  String? fromTime, toTime;

  Map<String, dynamic> toRow() => {
        'mode': mode,
        'title': _blank(title),
        'media_names': mediaNames,
        'seconds': seconds,
        'cycle_seconds': mode == 'mosaic' ? cycleSeconds : null,
        'fit': fit,
        'show_title': showTitle,
        'credits': _blank(credits),
        'logo': logo,
        'matte': matte,
        'position': position,
        'active': active,
        'starts_on': startsOn == null ? null : isoDate(startsOn!),
        'ends_on': endsOn == null ? null : isoDate(endsOn!),
        'from_time': fromTime,
        'to_time': toTime,
        'takeover': takeover,
        'every_seconds': every,
        'activity_id': activityId,
      };

  /// The first thing to fix before saving, or null.
  String? problem() {
    if (mode == 'videowall' && mediaNames.length != 1) return 'Pick one file for the videowall.';
    if (seconds != null && seconds! < 1) return 'Seconds must be at least 1.';
    if (cycleSeconds != null && cycleSeconds! < 1) return 'Cycle seconds must be at least 1.';
    if (matte < 0 || matte > 400) return 'Matte is 0 to 400 px.';
    if (every != null && every! <= (seconds ?? 0)) {
      return 'Show every: the gap must be longer than the seconds (a whole video needs its seconds set).';
    }
    if (takeover && activityId == null && endsOn == null && toTime == null) {
      return 'A takeover needs an end: set "Until" (a date or a time), or it takes over the wall for good.';
    }
    if (fromTime != null && toTime != null && toTime!.compareTo(fromTime!) <= 0) {
      return 'The end time is before the start time.';
    }
    if (startsOn != null && endsOn != null && endsOn!.isBefore(startsOn!)) {
      return 'The end date is before the start date.';
    }
    return null;
  }
}

/// The office's line about the wall, from the server's heartbeat (wall_status). ok is false when the server has not
/// reported for 60 s (its heartbeat is every 10 s), never reported, or its last Supabase call failed.
({String text, bool ok}) wallStatusLine(Map<String, dynamic>? r, DateTime now) {
  String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final seen = r?['seen_at'] == null ? null : DateTime.parse(r!['seen_at'] as String).toLocal();
  if (seen == null) return (text: 'Wall: the wall server has not reported yet.', ok: false);
  if (now.difference(seen).inSeconds >= 60) return (text: 'Wall not reporting since ${hm(seen)}: is the wall server running?', ok: false);
  final screens = (r!['screens'] as Map?) ?? const {};
  final on = screens.values.where((s) => (s as Map)['on'] == true).length;
  final errorAt = r['error_at'] == null ? null : DateTime.parse(r['error_at'] as String).toLocal();
  final failing = errorAt != null && !errorAt.isBefore(seen);
  return (
    text: '${r['playing'] ?? 'Wall'} · $on/${screens.length} screens on${failing ? ' · ${r['error']}' : ''}',
    ok: !failing,
  );
}

/// Screen codes as rows of the wall: letter = column, number = row (a1 top left). The server owns the grid size;
/// the office only lays out the codes it reports.
List<List<String>> wallGrid(Iterable<String> codes) {
  final rows = <int, List<String>>{};
  for (final c in codes) {
    final row = int.tryParse(c.substring(1));
    if (row != null) (rows[row] ??= []).add(c);
  }
  return [for (final r in (rows.keys.toList()..sort())) rows[r]!..sort()];
}
