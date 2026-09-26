// Equipment requests (/kit/): the catalogue search, the form's checks (mirroring request_equipment()) and what it sends.
import 'book.dart';
import 'schedule.dart' show plain;

const uses = {'class': 'For my class', 'lab': 'Lab work in the Tech Lab', 'home': 'To take home'};

typedef Item = ({int id, String name});

List<Item> catalogue(List<Object?> rows) =>
    [for (final r in rows.cast<Map<String, dynamic>>()) (id: r['id'] as int, name: r['name'] as String)];

/// Items whose name holds every typed word, ignoring case and accents: "esp dev" finds "ESP32 DevKit".
List<Item> search(List<Item> items, String q) {
  final words = [for (final w in plain(q).split(RegExp(r'\s+'))) if (w.isNotEmpty) w];
  return [for (final i in items) if (words.every(plain(i.name).contains)) i];
}

/// A local date ("2026-10-20") and time ("14:00") as an instant, or null when either is missing.
DateTime? localAt(String date, String time) => date.isEmpty || time.isEmpty ? null : DateTime.tryParse('${date}T$time');

/// The first problem with the form, or null. Same rules as request_equipment() in the database.
String? kitProblem({
  required String name,
  required String email,
  String number = '',
  required String use,
  DateTime? start,
  DateTime? end,
  String repeatUntil = '',
  required Map<int, int> picked,
  String other = '',
  String course = '',
}) {
  final contact = contactProblem(name: name, email: email, number: number);
  if (contact != null) return contact;
  if (!uses.containsKey(use)) return 'Say what it is for: a class, lab work or taking it home.';
  if (start == null || end == null) return 'Pick the date and times.';
  if (!end.isAfter(start)) return 'The end must be after the start.';
  if (end.difference(start).inDays > 90) return 'Ask for at most 90 days at a time.';
  if (repeatUntil.isNotEmpty && use != 'class') return 'Weekly repeats are for classes, up to 6 months.';
  if (picked.length > 20) return 'At most 20 different items per request.';
  if (picked.isEmpty && other.trim().length < 3) return 'Pick at least one item, or say what you need.';
  if (picked.values.any((q) => q < 1 || q > 100)) return 'Quantities are 1–100.';
  if (other.trim().length > 500 || course.trim().length > 100) {
    return 'Keep "something else" under 500 characters and the course under 100.';
  }
  return null;
}

/// The arguments of request_equipment().
Map<String, Object?> requestArgs({
  required String name,
  required String email,
  String number = '',
  required String use,
  String course = '',
  required DateTime start,
  required DateTime end,
  String repeatUntil = '',
  required Map<int, int> picked,
  String other = '',
  String website = '',
}) =>
    {
      'p_name': name,
      'p_email': email,
      'p_student_number': number,
      'p_use': use,
      'p_course': course,
      'p_starts_at': start.toUtc().toIso8601String(),
      'p_ends_at': end.toUtc().toIso8601String(),
      'p_repeat_until': repeatUntil.isEmpty ? null : repeatUntil,
      'p_items': [for (final e in picked.entries) {'item_id': e.key, 'qty': e.value}],
      'p_other': other,
      'p_website': website,
    };
