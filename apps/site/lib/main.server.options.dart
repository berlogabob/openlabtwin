// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:site/pages/schedule_page.dart' as _schedule_page;
import 'package:site/pages/tv_page.dart' as _tv_page;

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
    _schedule_page.SchedulePage: ClientTarget<_schedule_page.SchedulePage>(
      'schedule_page',
    ),
    _tv_page.TvPage: ClientTarget<_tv_page.TvPage>('tv_page'),
  },
);
