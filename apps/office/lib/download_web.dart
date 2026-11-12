import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadText(String filename, String content, String mime) {
  final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
