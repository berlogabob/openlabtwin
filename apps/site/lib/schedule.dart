// Lessons, filters and matching. Pure Dart (no DOM), so `dart test` covers it.
import 'dart:convert';

const defaultRoom = 'Lab. e Estudo de Jogos - Tech Lab (Oriente)';

class Lesson {
  const Lesson({
    required this.date,
    required this.start,
    required this.end,
    required this.course,
    this.groups = const [],
    this.teachers = const [],
    this.type = '',
    this.rooms = const [],
    this.programmes = const [],
    this.degrees = const [],
    this.layer = 'lesson',
    this.note = '',
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        date: j['date'] as String,
        start: j['start'] as String,
        end: j['end'] as String,
        course: j['course'] as String,
        groups: _strings(j['groups']),
        teachers: _strings(j['teachers']),
        type: j['type'] as String? ?? '',
        rooms: _strings(j['rooms']),
        programmes: _strings(j['programmes']),
        degrees: _strings(j['degrees']),
        layer: j['layer'] as String? ?? 'lesson',
        note: j['note'] as String? ?? '',
      );

  final String date, start, end, course, type, layer, note;
  final List<String> groups, teachers, rooms, programmes, degrees;
}

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) x as String];

List<Lesson> parseLessons(String json) =>
    [for (final j in jsonDecode(json) as List) Lesson.fromJson(j as Map<String, dynamic>)];

/// Filter fields in display order: URL key -> values of a lesson.
final fields = <String, List<String> Function(Lesson)>{
  'degree': (l) => l.degrees,
  'programme': (l) => l.programmes,
  'room': (l) => l.rooms,
  'teacher': (l) => l.teachers,
  'group': (l) => l.groups,
  'course': (l) => [l.course],
  'type': (l) => [l.type],
};

const labels = {
  'degree': 'Degree',
  'programme': 'Programme',
  'room': 'Room / lab',
  'teacher': 'Professor / staff',
  'group': 'Group',
  'course': 'Course',
  'type': 'Type',
};

/// Every value each field has anywhere, to tell a picked value (exact match) from typed text (substring).
Map<String, Set<String>> knownValues(List<Lesson> lessons) => {
      for (final e in fields.entries) e.key: {for (final l in lessons) ...e.value(l).where((v) => v.isNotEmpty)}
    };

// ponytail: Latin accents only (enough for Portuguese); Dart core has no NFD, add a normalizer if other scripts appear
const _fold = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i',
  'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// "computacao" finds "Computação".
String plain(String s) => s.toLowerCase().split('').map((c) => _fold[c] ?? c).join();

/// Values within one field are ORed. A known value matches exactly; typed text matches anywhere, ignoring accents.
bool matchesField(List<String> have, List<String> wanted, Set<String> known) =>
    wanted.isEmpty ||
    wanted.any((w) => known.contains(w) ? have.contains(w) : have.any((v) => plain(v).contains(plain(w))));

class Filters {
  Filters({Map<String, List<String>>? values, this.from = '', this.to = '', this.view = 'list', this.date = ''})
      : values = values ?? {};

  /// field -> chosen values. A present-but-empty 'room' means "any room" (absent means the default lab).
  final Map<String, List<String>> values;
  String from, to, view, date;

  factory Filters.parse(String query) {
    final all = Uri(query: query.startsWith('?') ? query.substring(1) : query).queryParametersAll;
    String one(String k) => (all[k] ?? const ['']).first;
    final view = one('view');
    return Filters(
      values: {
        for (final k in fields.keys)
          if (all.containsKey(k)) k: [for (final v in all[k]!) if (v.isNotEmpty) v]
      },
      from: one('from'),
      to: one('to'),
      view: const ['day', 'week', 'month'].contains(view) ? view : 'list',
      date: RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(one('date')) ? one('date') : '',
    );
  }

  /// Repeated keys for several values: ?teacher=A&teacher=B.
  String toQuery() {
    final parts = <String>[];
    void add(String k, String v) => parts.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
    for (final k in fields.keys) {
      final vs = values[k];
      if (vs == null) continue;
      if (vs.isEmpty && k == 'room') add(k, '');
      for (final v in vs) {
        add(k, v);
      }
    }
    if (from.isNotEmpty) add('from', from);
    if (to.isNotEmpty) add('to', to);
    if (view != 'list') {
      add('view', view);
      add('date', date);
    }
    return parts.join('&');
  }

  Filters copy() => Filters(
      values: {for (final e in values.entries) e.key: [...e.value]}, from: from, to: to, view: view, date: date);
}

class Result {
  const Result(this.hits, this.options);
  final List<Lesson> hits;

  /// Smart lists: per field, only the values that still have lessons under all the *other* filters.
  final Map<String, List<String>> options;
}

Result run(List<Lesson> lessons, Map<String, List<String>> wanted, Map<String, Set<String>> known, String from,
    String to) {
  final names = fields.keys.toList();
  final hits = <Lesson>[];
  final opts = {for (final n in names) n: <String>{}};
  for (final l in lessons) {
    final pass = [for (final n in names) matchesField(fields[n]!(l), wanted[n] ?? const [], known[n]!)];
    final inDates = (from.isEmpty || l.date.compareTo(from) >= 0) && (to.isEmpty || l.date.compareTo(to) <= 0);
    final fails = pass.where((p) => !p).length + (inDates ? 0 : 1);
    if (fails == 0) hits.add(l);
    if (fails > 1) continue;
    for (var j = 0; j < names.length; j++) {
      if (fails == 0 || !pass[j]) opts[names[j]]!.addAll(fields[names[j]]!(l).where((v) => v.isNotEmpty));
    }
  }
  return Result(hits, {
    for (final n in names) n: opts[n]!.toList()..sort((a, b) => plain(a).compareTo(plain(b)))
  });
}
