// Idea hub private link (/ideas/status/?t=…): the AI's version, matches, "I'd like to connect". Its own file: Jaspr
// allows one @client component per file.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../ideas.dart';

@client
class IdeaStatusPage extends StatefulComponent {
  const IdeaStatusPage({super.key});

  @override
  State<IdeaStatusPage> createState() => IdeaStatusPageState();
}

class IdeaStatusPageState extends State<IdeaStatusPage> {
  String token = '';
  IdeaView? view;
  String? error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    token = Uri.parse(web.window.location.href).queryParameters['t'] ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final j = token.isEmpty ? null : await rpc('idea_status', {'p_token': token});
      setState(() {
        if (j == null) {
          error = 'No idea found for this link.';
        } else {
          view = IdeaView.fromJson(j as Map<String, dynamic>);
        }
      });
    } catch (e) {
      setState(() => error = 'Could not load your idea: $e');
    }
  }

  Future<void> _connect(int other) async {
    try {
      await rpc('idea_connect', {'p_token': token, 'p_other': other});
      await _load();
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Component build(BuildContext context) {
    final v = view;
    return div(classes: 'book', [
      header([
        h1([a(href: 'ideas/', [.text('Your idea')])]),
        nav([a(href: 'ideas/', [.text('Share another')])]),
      ]),
      main_([
        if (error != null) p(classes: 'error', [.text(error!)]),
        if (v == null && error == null) p(classes: 'empty', [.text('Loading…')]),
        if (v != null) ...[
          if (v.title != null) p(classes: 'idea-title', [.text(v.title!)]),  // h2 is the uppercase day-heading style
          if (v.summary != null) p([.text(v.summary!)]),
          if (v.keywords.isNotEmpty) p(classes: 'chips', [for (final k in v.keywords) span(classes: 'chip', [.text(k)])]),
          details([summary([.text('What you wrote')]), p([.text(v.body)])]),
          p(classes: 'status', [.text(v.stage)]),
          for (final m in v.matches)
            article(classes: m.kind == 'complementary' ? 'event' : 'booking', [
              p(classes: 'course', [.text(m.title)]),
              p([.text('${m.firstName} · ${m.kind == 'complementary' ? 'complementary' : 'similar'} · ${m.reason}')]),
              if (m.email != null)
                p([.text('Connected: '), a(href: 'mailto:${m.email}', [.text(m.email!)]), if (m.link != null) ...[.text(' · '), a(href: m.link!, [.text(m.link!)])]])
              else if (m.iConnected)
                p([.text(m.theyConnected ? 'Both connected.' : 'You asked to connect. Their contact appears when they do too.')])
              else
                button(type: ButtonType.button, onClick: () => _connect(m.other),
                    [.text(m.theyConnected ? '${m.firstName} wants to connect: connect back' : 'I\'d like to connect')]),
            ]),
          p([a(href: 'book/?project=${Uri.encodeQueryComponent(v.title ?? v.body)}', [.text('Book a consultation about this idea')])]),
        ],
      ]),
    ]);
  }
}
