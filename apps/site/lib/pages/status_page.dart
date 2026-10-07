// "Book me" status page (/book/status/?t=…): what a student's private link shows. Its own file: Jaspr allows one @client
// component per file.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../calendar.dart';

String _time(DateTime d) => '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

@client
class StatusPage extends StatefulComponent {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => StatusPageState();
}

class StatusPageState extends State<StatusPage> {
  String? message, proposal;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    final t = Uri.parse(web.window.location.href).queryParameters['t'] ?? '';
    try {
      final rows = t.isEmpty ? const [] : await rpc('consultation_status', {'p_token': t}) as List;
      if (rows.isEmpty) return setState(() => message = 'No request found for this link.');
      final r = rows.first as Map<String, dynamic>;
      final start = DateTime.parse(r['starts_at'] as String).toLocal(), end = DateTime.parse(r['ends_at'] as String).toLocal();
      final ps = r['proposed_starts_at'] as String?, pe = r['proposed_ends_at'] as String?;
      setState(() {
        message = '${statusLabels[r['status']] ?? r['status']} · ${dayName(iso(start))}, ${_time(start)}–${_time(end)}';
        proposal = r['status'] == 'proposed' && ps != null && pe != null
            ? 'New time proposed: ${dayName(iso(DateTime.parse(ps).toLocal()))}, ${_time(DateTime.parse(ps).toLocal())}–${_time(DateTime.parse(pe).toLocal())}'
            : null;
      });
    } catch (e) {
      setState(() => message = 'Could not load the status: $e');
    }
  }

  Future<void> _answer(bool accept) async {
    final t = Uri.parse(web.window.location.href).queryParameters['t'] ?? '';
    try {
      await rpc('answer_proposal', {'p_token': t, 'p_accept': accept});
      await _load();
    } catch (e) {
      setState(() => message = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Component build(BuildContext context) => div(classes: 'book', [
        header([h1([a(href: './', [.text('Your consultation')])])]),
        main_([
          p(classes: 'status', [.text(message ?? 'Loading…')]),
          if (proposal != null) ...[
            p([.text(proposal!)]),
            button(type: ButtonType.button, onClick: () => _answer(true), [.text('Accept')]),
            button(type: ButtonType.button, onClick: () => _answer(false), [.text('Decline')]),
          ],
        ]),
      ]);
}
