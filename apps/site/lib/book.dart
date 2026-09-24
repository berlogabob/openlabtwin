// "Book me": slot grouping, form checks (mirroring request_consultation()), and the three public RPC calls.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'calendar.dart';

/// Public by design: anon has no table grants; it can only call the three functions below.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

typedef Slot = ({String iso, DateTime start, DateTime end}); // iso: exactly what free_slots returned, sent back as is

/// Slots grouped by local date, in order.
Map<String, List<Slot>> byDay(List<Slot> slots) {
  final out = <String, List<Slot>>{};
  for (final s in slots..sort((a, b) => a.start.compareTo(b.start))) {
    out.putIfAbsent(iso(s.start), () => []).add(s);
  }
  return out;
}

/// The first problem with name, email, link or student number: the rules of check_contact() in the database.
String? contactProblem({required String name, required String email, String link = '', String number = ''}) {
  final n = name.trim(), e = email.trim(), l = link.trim(), s = number.trim();
  if (n.length < 2 || n.length > 100) return 'Please give your name (2–100 characters).';
  if (e.length < 3 || e.length > 200 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return 'Please give a valid email.';
  if (l.isNotEmpty && (l.length > 500 || !RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(l))) {
    return 'The link must start with http:// or https://.';
  }
  if (s.isNotEmpty && !RegExp(r'^[A-Za-z0-9-]{1,30}$').hasMatch(s)) return 'The student number can only have letters, digits and dashes.';
  return null;
}

/// The first problem with the Book me form, or null (mirrors request_consultation()).
String? formProblem({required String name, required String email, required String project, String link = '', String number = ''}) {
  final p = project.trim();
  return contactProblem(name: name, email: email, link: link, number: number) ??
      (p.length < 10 || p.length > 2000 ? 'Describe your project in 10–2000 characters.' : null);
}

const statusLabels = {
  'requested': 'Requested: waiting for an answer',
  'approved': 'Approved',
  'rejected': 'Declined',
  'cancelled': 'Cancelled',
  'done': 'Done',
};

/// `POST /rest/v1/rpc/<fn>`. Throws the database's readable message on failure.
Future<Object?> rpc(String fn, Map<String, Object?> args) async {
  final r = await http.post(Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'),
      headers: {'apikey': supabaseKey, 'Authorization': 'Bearer $supabaseKey', 'Content-Type': 'application/json'},
      body: jsonEncode(args));
  final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  if (r.statusCode >= 300) {
    throw Exception(body is Map && body['message'] is String ? body['message'] : 'Something went wrong (${r.statusCode}).');
  }
  return body;
}

Future<List<Slot>> freeSlots(String from, String to) async => [
      for (final s in (await rpc('free_slots', {'p_from': from, 'p_to': to}) as List).cast<Map<String, dynamic>>())
        (iso: s['starts_at'] as String, start: DateTime.parse(s['starts_at'] as String).toLocal(), end: DateTime.parse(s['ends_at'] as String).toLocal())
    ];
