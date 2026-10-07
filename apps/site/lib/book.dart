// "Book me": form checks (mirroring request_consultation()) and the public RPC call.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Public by design: anon has no table grants; it can only call the functions in the database that the forms use.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// The label every public form uses for the student number: the lab's local ID for a person (staff give their staff number).
const numberLabel = 'Student number (staff: your staff number)';

/// The first problem with name, email, link or student number: the rules of check_contact() in the database.
String? contactProblem({required String name, required String email, String link = '', required String number}) {
  final n = name.trim(), e = email.trim(), l = link.trim(), s = number.trim();
  if (n.length < 2 || n.length > 100) return 'Please give your name (2–100 characters).';
  if (e.length < 3 || e.length > 200 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return 'Please give a valid email.';
  if (l.isNotEmpty && (l.length > 500 || !RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(l))) {
    return 'The link must start with http:// or https://.';
  }
  if (s.isEmpty) return 'Please give your student number (staff: your staff number).';
  if (!RegExp(r'^[A-Za-z0-9-]{1,30}$').hasMatch(s)) return 'The student number can only have letters, digits and dashes.';
  return null;
}

/// The time wheel: hours 08–21 and quarter-hour minutes.
final hours = [for (var h = 8; h <= 21; h++) '$h'.padLeft(2, '0')];
const minutesOfHour = ['00', '15', '30', '45'];

/// Lengths a student can ask for, in minutes.
const lengths = [15, 30, 45, 60, 90];

/// The first problem with the Book me form, or null (mirrors request_consultation()): only the student number is
/// required; a name, an email (else number@iade.pt) and the line about the need are optional. [start] is the local time asked for.
String? formProblem(
    {String name = '', String email = '', required String number, String need = '', DateTime? start, DateTime? now}) {
  final n = need.trim(), e = email.trim(), s = number.trim();
  if (s.isEmpty) return 'Please give your student number (staff: your staff number).';
  if (!RegExp(r'^[A-Za-z0-9-]{1,30}$').hasMatch(s)) return 'The student number can only have letters, digits and dashes.';
  if (name.trim().isNotEmpty && (name.trim().length < 2 || name.trim().length > 100)) return 'The name is 2–100 characters, or leave it empty.';
  if (e.isNotEmpty && (e.length > 200 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e))) return 'Please give a valid email, or leave it empty.';
  if (n.isNotEmpty && (n.length < 3 || n.length > 300)) return 'Keep it to a line (3–300 characters), or leave it empty.';
  if (start == null) return 'Pick a date and time.';
  if (start.isBefore((now ?? DateTime.now()).add(const Duration(hours: 1)))) return 'Please pick a time at least an hour from now.';
  return null;
}

const statusLabels = {
  'requested': 'Requested: waiting for an answer',
  'proposed': 'A new time is proposed',
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
