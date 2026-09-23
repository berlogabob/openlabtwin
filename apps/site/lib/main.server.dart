/// Server entrypoint: runs only during the static build (pre-rendering).
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'app.dart';
import 'main.server.options.dart';

/// '/' locally; the GitHub Pages build passes --dart-define=BASE=/openlabtwin/.
const base = String.fromEnvironment('BASE', defaultValue: '/');

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);
  runApp(Document(
    title: 'IADE Schedule',
    lang: 'en',
    base: base,
    head: [link(rel: 'stylesheet', href: 'style.css')],
    body: const App(),
  ));
}
