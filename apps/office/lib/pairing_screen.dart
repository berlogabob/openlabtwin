import 'package:material_ui/material_ui.dart';

import 'download.dart';
import 'pairing_logic.dart';
import 'scan_widget.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, this.camera = true});
  final bool camera;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final boxes = <String>[];
  final consoles = <String>[];
  int step = 0;

  @override
  Widget build(BuildContext context) {
    final scans = step == 0 ? boxes : consoles;
    final unique = scans
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final result = matchPairs(boxes, consoles);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair boxes and consoles')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (step < 2) ...[
            Text(
              step == 0 ? 'Scan all boxes' : 'Scan all consoles',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            CodeCapture(
              key: ValueKey(step),
              camera: widget.camera,
              onCode: (code) => setState(() => scans.add(code)),
            ),
            Text('${unique.length} scanned'),
            for (final serial in unique)
              ListTile(
                title: Text(serial),
                trailing: const Icon(Icons.close),
                onTap: () => setState(
                  () => scans.removeWhere(
                    (s) => s.trim().toUpperCase() == serial,
                  ),
                ),
              ),
            FilledButton(
              onPressed: () => setState(() => step++),
              child: Text(step == 0 ? 'Done with boxes' : 'Done with consoles'),
            ),
          ] else ...[
            Text(
              'Matched: ${result.matched.length} · Move: ${result.assignments.length} · Empty boxes: ${result.leftoverBoxes.length} · Consoles without a box: ${result.leftoverConsoles.length}',
            ),
            const ListTile(title: Text('Matched')),
            for (final serial in result.matched) ListTile(title: Text(serial)),
            const ListTile(title: Text('Move console into box')),
            for (final (box, console) in result.assignments)
              ListTile(title: Text('Put console $console into box $box')),
            const ListTile(title: Text('Empty boxes left')),
            for (final serial in result.leftoverBoxes)
              ListTile(title: Text(serial)),
            const ListTile(title: Text('Consoles without a box')),
            for (final serial in result.leftoverConsoles)
              ListTile(title: Text(serial)),
            const ListTile(title: Text('Scanned twice')),
            for (final serial in result.duplicateBoxes)
              ListTile(title: Text('Box $serial')),
            for (final serial in result.duplicateConsoles)
              ListTile(title: Text('Console $serial')),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => downloadText(
                    'pairing.csv',
                    pairingCsv(result),
                    'text/csv;charset=utf-8',
                  ),
                  child: const Text('Download CSV'),
                ),
                FilledButton(
                  onPressed: () {
                    downloadText(
                      'sticker.html',
                      stickerHtml(result),
                      'text/html;charset=utf-8',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Open sticker.html and print it.'),
                      ),
                    );
                  },
                  child: const Text('Print stickers'),
                ),
                TextButton(
                  onPressed: () => setState(() => step = 1),
                  child: const Text('Back to consoles'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    boxes.clear();
                    consoles.clear();
                    step = 0;
                  }),
                  child: const Text('Start over'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
