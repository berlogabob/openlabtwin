// "Book me" form (/book/): any date and time, a length, name, email, one line, then the private status link.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';

@client
class BookPage extends StatefulComponent {
  const BookPage({super.key});

  @override
  State<BookPage> createState() => BookPageState();
}

class BookPageState extends State<BookPage> {
  String date = '', time = '', name = '', email = '', number = '', need = '', website = '';
  int minutes = 30;
  String? error, token;
  bool sending = false, needTime = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final p = Uri.parse(web.window.location.href).queryParameters['project'] ?? ''; // from "Book a consultation about this idea"
    need = p.length > 300 ? p.substring(0, 300) : p;
  }

  /// The asked-for local time, or null while the date or time is empty.
  DateTime? get _start => date.isEmpty || time.isEmpty ? null : DateTime.tryParse('${date}T$time');

  Future<void> _send() async {
    final problem = formProblem(name: name, email: email, number: number, need: need, start: _start);
    if (problem != null) {
      return setState(() {
        error = problem;
        needTime = _start == null;
      });
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('request_consultation', {
        'p_name': name, 'p_email': email, 'p_project': need, 'p_link': '', 'p_starts_at': _start!.toUtc().toIso8601String(), 'p_minutes': minutes,
        'p_student_number': number, 'p_website': website,
      });
      setState(() => token = t as String);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      setState(() => sending = false);
    }
  }

  Component _field(String caption, String value, void Function(String) set, {InputType type = InputType.text}) =>
      label([
        .text(caption),
        input<String>(type: type, value: value, onInput: (v) => set(v)),
      ]);

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    return div(classes: 'book', [
      header([
        h1([a(href: './', [.text('Book time in the lab')])]),
        nav([a(href: './', [.text('Schedule')])]),
      ]),
      main_([
        if (token != null)
          section(classes: 'done', [
            h2([.text('Request sent')]),
            p([.text('Bookmark this private link to see when it is approved:')]),
            p([a(href: link, [.text(link)])]),
          ])
        else ...[
          p([.text('Book time with Andrey in the Tech Lab. Ask for any date and time; you get an answer on your private link, and a different time may be proposed.')]),
          if (needTime) p(classes: 'error', [.text(error!)]),
          div(classes: 'form', [
            _field('Date', date, (v) => setState(() => date = v), type: InputType.date),
            _field('Time', time, (v) => setState(() => time = v), type: InputType.time),
            label([
              .text('Length'),
              select(
                value: '$minutes',
                onChange: (v) => setState(() => minutes = int.parse(v.first)),
                [for (final m in lengths) option(value: '$m', [.text('$m minutes')])],
              ),
            ]),
          ]),
          div(classes: 'form', [
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field(numberLabel, number, (v) => number = v),
            _field('What do you need?', need, (v) => need = v),
            // honeypot: hidden from people, bots fill it in
            label(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
              .text('Website'),
              input<String>(type: InputType.text, value: website, attributes: {'tabindex': '-1', 'autocomplete': 'off'}, onInput: (v) => website = v),
            ]),
            button(type: ButtonType.button, disabled: sending, onClick: _send, [.text(sending ? 'Sending…' : 'Send request')]),
            if (error != null && !needTime) p(classes: 'error', [.text(error!)]),
            p(classes: 'note', [.text('Your request is saved in your lab history, visible to lab staff only.')]),
            p(classes: 'note', [.text('Need equipment for a class, lab work or a project? '), a(href: 'kit/', [.text('Ask for it here')])]),
          ]),
        ],
      ]),
    ]);
  }
}
