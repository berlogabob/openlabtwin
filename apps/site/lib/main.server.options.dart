// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:site/pages/book_page.dart' as _book_page;
import 'package:site/pages/idea_status_page.dart' as _idea_status_page;
import 'package:site/pages/ideas_page.dart' as _ideas_page;
import 'package:site/pages/kit_page.dart' as _kit_page;
import 'package:site/pages/kit_status_page.dart' as _kit_status_page;
import 'package:site/pages/schedule_page.dart' as _schedule_page;
import 'package:site/pages/status_page.dart' as _status_page;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _book_page.BookPage: ClientTarget<_book_page.BookPage>('book_page'),
    _idea_status_page.IdeaStatusPage:
        ClientTarget<_idea_status_page.IdeaStatusPage>('idea_status_page'),
    _ideas_page.IdeasPage: ClientTarget<_ideas_page.IdeasPage>('ideas_page'),
    _kit_page.KitPage: ClientTarget<_kit_page.KitPage>('kit_page'),
    _kit_status_page.KitStatusPage:
        ClientTarget<_kit_status_page.KitStatusPage>('kit_status_page'),
    _schedule_page.SchedulePage: ClientTarget<_schedule_page.SchedulePage>(
      'schedule_page',
    ),
    _status_page.StatusPage: ClientTarget<_status_page.StatusPage>(
      'status_page',
    ),
  },
);
