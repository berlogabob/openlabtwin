// "Book me" form (/book/): any date and time, a length, name, email, one line, then the private status link.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../calendar.dart';

@client
class BookPage extends StatefulComponent {
  const BookPage({super.key});

  @override
  State<BookPage> createState() => BookPageState();
}

class BookPageState extends State<BookPage> {
  String date = '', name = '', email = '', number = '', need = '', website = '';
  int minutes = 30, hourIdx = 0, minIdx = 0; // the wheel starts at 08:00

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
  DateTime? get _start => date.isEmpty ? null : DateTime.tryParse('${date}T${hours[hourIdx]}:${minutesOfHour[minIdx]}');

  Future<void> _send() async {
    final problem = formProblem(name: name, email: email, number: number, need: need, start: _start);
    if (problem != null) {
      return setState(() {
        error = problem;
        needTime = date.isEmpty;
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

  /// One column of the time wheel: scroll (or click) to roll it; the middle row is the pick.
  Component _wheel(List<String> items, int index, void Function(int) pick) => div(
        classes: 'wheel-col',
        events: {
          'scroll': (e) {
            final i = ((e.target as web.HTMLElement).scrollTop / 36).round().clamp(0, items.length - 1);
            if (i != index) pick(i);
          },
        },
        [
          for (var i = 0; i < items.length; i++)
            div(
              classes: i == index ? 'wheel-item on' : 'wheel-item',
              events: {'click': (e) => ((e.currentTarget as web.HTMLElement).parentElement as web.HTMLElement).scrollTop = i * 36},
              [.text(items[i])],
            ),
        ],
      );

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
            // Jaspr hands date/time inputs a DateTime, not a String: read the raw value instead
            label([
              .text('Date'),
              input<String>(
                type: InputType.date,
                value: date,
                attributes: {'min': iso(DateTime.now())},
                events: {'input': (e) => setState(() => date = (e.target as web.HTMLInputElement).value)},
              ),
            ]),
            div(classes: 'wheel-box', [
              span([.text('Time')]),
              div(classes: 'wheel', [
                _wheel(hours, hourIdx, (n) => setState(() => hourIdx = n)),
                span(classes: 'wheel-sep', [.text(':')]),
                _wheel(minutesOfHour, minIdx, (n) => setState(() => minIdx = n)),
              ]),
            ]),
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
            _field('Name (optional)', name, (v) => name = v),
            _field('Email (optional, else your number@iade.pt)', email, (v) => email = v, type: InputType.email),
            _field(numberLabel, number, (v) => number = v),
            _field('What do you need? (optional)', need, (v) => need = v),
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
