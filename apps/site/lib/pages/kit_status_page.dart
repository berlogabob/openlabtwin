// Equipment request status (/kit/status/?t=…): what the private link shows. Its own file: one @client component per file.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../calendar.dart';

String _time(DateTime d) => '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

@client
class KitStatusPage extends StatefulComponent {
  const KitStatusPage({super.key});

  @override
  State<KitStatusPage> createState() => KitStatusPageState();
}

class KitStatusPageState extends State<KitStatusPage> {
  String? message;
  List<String> lines = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    final t = Uri.parse(web.window.location.href).queryParameters['t'] ?? '';
    try {
      final rows = t.isEmpty ? const [] : await rpc('equipment_status', {'p_token': t}) as List;
      if (rows.isEmpty) return setState(() => message = 'No request found for this link.');
      final r = rows.first as Map<String, dynamic>;
      final start = DateTime.parse(r['starts_at'] as String).toLocal(), end = DateTime.parse(r['ends_at'] as String).toLocal();
      final when = iso(start) == iso(end)
          ? '${dayName(iso(start))}, ${_time(start)}–${_time(end)}'
          : '${dayName(iso(start))} to ${dayName(iso(end))}';
      setState(() {
        message = '${statusLabels[r['status']] ?? r['status']} · $when${r['rrule'] == null ? '' : ' · every week'}';
        lines = [for (final i in (r['items'] as List).cast<Map<String, dynamic>>()) '${i['qty']} × ${i['name']}'];
      });
    } catch (e) {
      setState(() => message = 'Could not load the status: $e');
    }
  }

  @override
  Component build(BuildContext context) => div(classes: 'book', [
        header([h1([a(href: '../', [.text('Your equipment request')])])]),
        main_([
          p(classes: 'status', [.text(message ?? 'Loading…')]),
          if (lines.isNotEmpty) ul([for (final l in lines) li([.text(l)])]),
        ]),
      ]);
}
