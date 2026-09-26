// Paper loan archive: sheets the node's reader has read, checked one by one against their photo, then approved as loans.
import 'package:flutter/material.dart';

import 'data.dart';
import 'inventory.dart';
import 'logic.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.refs});
  final Refs refs;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  late Future<List<Rec>> data = archiveSheets();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Paper archive'), actions: [IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = archiveSheets()))]),
        body: FutureBuilder<List<Rec>>(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final rows = snap.data;
            if (rows == null) return const Center(child: CircularProgressIndicator());
            final extracted = rows.where((r) => r['status'] == 'extracted').toList().reversed.toList();
            final waiting = rows.where((r) => r['status'] == 'new').length;
            final errors = rows.where((r) => r['error'] != null).length;
            return ListView(
              children: [
                ListTile(title: Text('$waiting waiting for the reader · $errors with errors')),
                if (extracted.isEmpty) const ListTile(title: Text('Nothing to check.')),
                for (final sheet in extracted)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(sheet['file_name'] as String),
                    subtitle: Text('${_photoDate(sheet['photo_at'])} · ${_extractedName(sheet)} · ${_lines(sheet).length} lines'),
                    onTap: () async {
                      if (await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SheetPage(refs: widget.refs, sheet: sheet))) == true) {
                        setState(() => data = archiveSheets());
                      }
                    },
                  ),
              ],
            );
          },
        ),
      );
}

String _photoDate(Object? value) => value == null ? 'no photo date' : isoDate(DateTime.parse(value as String).toLocal());
Map _extracted(Rec sheet) => (sheet['extracted'] as Map?) ?? {};
String _extractedName(Rec sheet) => _extracted(sheet)['name']?.toString() ?? 'unknown student';
List<Rec> _lines(Rec sheet) => [for (final l in (_extracted(sheet)['lines'] as List?) ?? []) {'item_text': l is Map ? l['text'] : l, 'qty': l is Map ? l['qty'] : 1}];

class SheetPage extends StatefulWidget {
  const SheetPage({super.key, required this.refs, required this.sheet});
  final Refs refs;
  final Rec sheet;

  @override
  State<SheetPage> createState() => _SheetPageState();
}

class _SheetPageState extends State<SheetPage> {
  late final course = TextEditingController(text: _extracted(widget.sheet)['course']?.toString() ?? '');
  late final outOn = TextEditingController(text: _extracted(widget.sheet)['out_on']?.toString() ?? '');
  late final backOn = TextEditingController(text: _extracted(widget.sheet)['back_on']?.toString() ?? '');
  late final lines = _lines(widget.sheet);
  late int? personId = personFor(_extracted(widget.sheet), widget.refs.people.where((p) => p['kind'] == 'student').toList());
  late Future<String?> image = _image();
  bool saving = false;

  Future<String?> _image() async => widget.sheet['image_path'] == null ? null : archiveImageUrl(widget.sheet['image_path'] as String);

  Future<void> _newStudent() async {
    final n = TextEditingController(), number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New student'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Student name')),
          TextField(controller: number, decoration: const InputDecoration(labelText: 'Student number')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add'))],
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    try {
      final p = await addPerson(n.text, 'student', '');
      if (number.text.trim().isNotEmpty) await setStudentNumber(p['id'] as int, number.text.trim());
      widget.refs.people.add({...p, if (number.text.trim().isNotEmpty) 'student_number': number.text.trim()});
      setState(() => personId = p['id'] as int);
    } catch (e) {
      if (mounted) say(context, 'Could not add student: $e');
    }
  }

  Future<void> _save(bool approve) async {
    try {
      final loans = sheetLoans(personId: personId, course: course.text, outOn: outOn.text, backOn: backOn.text, lines: lines);
      setState(() => saving = true);
      if (approve) {
        await approveSheet(widget.sheet['id'] as int, loans);
      } else {
        await rejectSheet(widget.sheet['id'] as int);
      }
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError catch (e) {
      if (mounted) say(context, e.message as String);
      setState(() => saving = false);
    } catch (e) {
      if (mounted) say(context, 'Could not save: $e');
      setState(() => saving = false);
    }
  }

  Widget _form(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: DropdownButton<int?>(
                value: personId,
                isExpanded: true,
                hint: const Text('Student'),
                items: [for (final p in widget.refs.people.where((p) => p['kind'] == 'student')) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
                onChanged: (v) => setState(() => personId = v),
              ),
            ),
            TextButton(onPressed: _newStudent, child: const Text('New student')),
          ]),
          TextField(controller: course, decoration: const InputDecoration(labelText: 'Course')),
          TextField(controller: outOn, decoration: const InputDecoration(labelText: 'Out on (YYYY-MM-DD)')),
          TextField(controller: backOn, decoration: const InputDecoration(labelText: 'Back on (YYYY-MM-DD)')),
          const SizedBox(height: 12),
          for (var i = 0; i < lines.length; i++) _line(i),
          OutlinedButton.icon(onPressed: () => setState(() => lines.add({'item_text': '', 'qty': 1})), icon: const Icon(Icons.add), label: const Text('Add line')),
          ExpansionTile(title: const Text('Transcription'), children: [ListTile(title: Text(widget.sheet['raw_text'] as String? ?? ''))]),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton(onPressed: saving ? null : () => _save(false), child: const Text('Reject')),
            const Spacer(),
            FilledButton(onPressed: saving ? null : () => _save(true), child: const Text('Approve')),
          ]),
        ],
      );

  Widget _line(int index) {
    final line = lines[index];
    // kept on the line, so a redraw neither asks the database again nor resets what was typed
    final text = line['_text'] ??= TextEditingController(text: line['item_text']?.toString() ?? '');
    final qty = line['_qty'] ??= TextEditingController(text: '${line['qty'] ?? 1}');
    return FutureBuilder<List<Rec>>(
      future: line['_matches'] ??= matchItem(line['item_text']?.toString() ?? ''),
      builder: (context, snap) {
        final matches = snap.data ?? [];
        if (line['item_id'] == null && line['item_chosen'] != true && matches.isNotEmpty && (matches.first['score'] as num) >= .5) line['item_id'] = matches.first['id'];
        final values = [for (final m in matches) m['id'] as int];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: text, decoration: const InputDecoration(labelText: 'Item text'), onChanged: (v) => line['item_text'] = v)),
                SizedBox(width: 70, child: TextField(controller: qty, decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number, onChanged: (v) => line['qty'] = num.tryParse(v) ?? 1)),
                IconButton(tooltip: 'Remove line', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => lines.removeAt(index))),
              ]),
              DropdownButton<int?>(
                value: values.contains(line['item_id']) ? line['item_id'] as int : null,
                isExpanded: true,
                hint: const Text('No item (keep the text)'),
                items: [const DropdownMenuItem<int?>(value: null, child: Text('No item (keep the text)')), for (final m in matches) DropdownMenuItem(value: m['id'] as int, child: Text('${m['name']} (${m['score']})'))],
                onChanged: (v) => setState(() {
                  line['item_chosen'] = true;
                  line['item_id'] = v;
                }),
              ),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.sheet['file_name'] as String)),
        body: LayoutBuilder(builder: (context, box) {
          final form = _form(context);
          final picture = FutureBuilder<String?>(future: image, builder: (context, snap) => snap.data == null ? const Center(child: Text('No image')) : InteractiveViewer(child: Image.network(snap.data!, fit: BoxFit.contain)));
          return box.maxWidth >= 700 ? Row(children: [Expanded(child: picture), Expanded(child: form)]) : Column(children: [Expanded(child: picture), Expanded(child: form)]);
        }),
      );
}
