import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List?> pickPhoto() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..setAttribute('capture', 'environment');
  final chosen = Completer<web.File?>();
  input.addEventListener('change', ((web.Event _) {
    chosen.complete(input.files?.item(0));
  }).toJS);
  input.addEventListener('cancel', ((web.Event _) {
    chosen.complete(null);
  }).toJS);
  input.click();
  final file = await chosen.future;
  if (file == null) return null;
  final url = web.URL.createObjectURL(file);
  try {
    final image = web.HTMLImageElement();
    final loaded = Completer<void>();
    image.onload = ((web.Event _) => loaded.complete()).toJS;
    image.onerror = ((web.Event _) => loaded.completeError(StateError('Could not read image'))).toJS;
    image.src = url;
    await loaded.future;
    final scale = min(1.0, 1600 / max(image.naturalWidth, image.naturalHeight));
    final canvas = web.HTMLCanvasElement()
      ..width = max(1, (image.naturalWidth * scale).round())
      ..height = max(1, (image.naturalHeight * scale).round());
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    final blob = Completer<web.Blob?>();
    canvas.toBlob(((web.Blob? value) => blob.complete(value)).toJS, 'image/jpeg', 0.85.toJS);
    final jpeg = await blob.future;
    if (jpeg == null) throw StateError('Could not encode image');
    return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
