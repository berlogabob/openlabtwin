import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CodeCapture extends StatefulWidget {
  const CodeCapture({super.key, required this.onCode, this.camera = true});
  final void Function(String code) onCode;
  final bool camera;

  @override
  State<CodeCapture> createState() => _CodeCaptureState();
}

class _CodeCaptureState extends State<CodeCapture> {
  late bool camera = widget.camera;
  final text = TextEditingController();
  final focus = FocusNode();
  final seen = <String, DateTime>{};
  final scanner = MobileScannerController(formats: const [
    BarcodeFormat.qrCode,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.codabar,
    BarcodeFormat.itf14,
    BarcodeFormat.dataMatrix,
  ]);

  void _detect(BarcodeCapture capture) {
    final now = DateTime.now();
    seen.removeWhere((_, time) => now.difference(time) >= const Duration(seconds: 2));
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.isEmpty || seen.containsKey(code)) continue;
      seen[code] = now;
      widget.onCode(code);
    }
  }

  void _submit(String value) {
    final codes = value.split(RegExp(r'[,\s]+')).where((code) => code.isNotEmpty);
    if (codes.isEmpty) return;
    text.clear();
    focus.requestFocus();
    for (final code in codes) {
      widget.onCode(code);
    }
  }

  @override
  void dispose() {
    scanner.dispose();
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (camera)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: MobileScanner(
              controller: scanner,
              onDetect: _detect,
              errorBuilder: (_, _) => const Center(child: Text('No camera available: type the code below.')),
            ),
          ),
        ),
      TextButton(
        onPressed: () => setState(() => camera = !camera),
        child: Text(camera ? 'Camera off' : 'Camera on'),
      ),
      TextField(
        controller: text,
        focusNode: focus,
        autofocus: false,
        decoration: InputDecoration(
          labelText: 'Type or scan with a USB scanner',
          suffixIcon: IconButton(tooltip: 'Clear', onPressed: text.clear, icon: const Icon(Icons.clear)),
        ),
        onSubmitted: _submit,
      ),
    ],
  );
}
