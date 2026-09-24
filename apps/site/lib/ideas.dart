// Idea hub: form checks (mirroring submit_idea()) and the private status view parsed from idea_status().
import 'book.dart';

/// The first problem with the idea form, or null.
String? ideaProblem({
  required String name,
  required String email,
  required String body,
  String link = '',
  String canBring = '',
  String lookingFor = '',
  String number = '',
}) {
  final b = body.trim();
  return contactProblem(name: name, email: email, link: link, number: number) ??
      (b.length < 10 || b.length > 4000 ? 'Describe your idea in 10–4000 characters.' : null) ??
      (canBring.length > 500 || lookingFor.length > 500 ? '"I can bring" and "I\'m looking for" are at most 500 characters each.' : null);
}

class IdeaMatch {
  IdeaMatch.fromJson(Map<String, dynamic> j)
      : other = j['other'] as int,
        kind = j['kind'] as String,
        reason = j['reason'] as String? ?? '',
        title = j['title'] as String? ?? 'An idea',
        firstName = j['first_name'] as String? ?? '',
        iConnected = j['i_connected'] == true,
        theyConnected = j['they_connected'] == true,
        email = (j['contact'] as Map?)?['email'] as String?,
        link = (j['contact'] as Map?)?['link'] as String?;

  final int other;
  final String kind, reason, title, firstName;
  final bool iConnected, theyConnected;
  final String? email, link; // only once both connected
}

class IdeaView {
  IdeaView.fromJson(Map<String, dynamic> j)
      : body = (j['idea'] as Map)['body'] as String,
        status = (j['idea'] as Map)['status'] as String,
        processed = (j['idea'] as Map)['processed'] == true,
        title = (j['idea'] as Map)['title'] as String?,
        summary = (j['idea'] as Map)['summary'] as String?,
        keywords = [for (final k in ((j['idea'] as Map)['keywords'] as List? ?? const [])) k as String],
        matches = [for (final m in (j['matches'] as List? ?? const [])) IdeaMatch.fromJson(m as Map<String, dynamic>)];

  final String body, status;
  final bool processed;
  final String? title, summary;
  final List<String> keywords;
  final List<IdeaMatch> matches;

  String get stage => switch (status) {
        'approved' => matches.isEmpty ? 'Approved. No matches yet; new ideas are matched every 15 minutes.' : 'Approved. Your matches:',
        'archived' => 'Archived by the lab.',
        _ => processed ? 'Waiting for the lab to approve it before matching.' : 'The AI is reading your idea…',
      };
}
