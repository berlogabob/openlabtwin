import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'download.dart';
import 'report_logic.dart';

typedef ReportLoader = Future<(List<Rec>, List<Rec>, List<Rec>)> Function(String from, String to);

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.refs, this.loader = reportSource});
  final Refs refs;
  final ReportLoader loader;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTime from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime to = DateTime.now();
  late Future<(List<Rec>, List<Rec>, List<Rec>)> data = _load();

  String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Future<(List<Rec>, List<Rec>, List<Rec>)> _load() => widget.loader(_date(from), _date(to));

  Future<void> _pick(bool start) async {
    final selected = await showDatePicker(context: context, initialDate: start ? from : to, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (selected != null) setState(() { if (start) { from = selected; } else { to = selected; } });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Equipment requests report')),
        body: FutureBuilder<(List<Rec>, List<Rec>, List<Rec>)>(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final loaded = snap.data;
            if (loaded == null) return const Center(child: CircularProgressIndicator());
            final (activities, lines, movements) = loaded;
            final rows = bookingReport(activities: activities, lines: lines, movements: movements, people: widget.refs.people, itemNames: widget.refs.itemNames, from: _date(from), to: _date(to));
            final outstanding = rows.fold<num>(0, (sum, row) => sum + (row['outstanding'] as num));
            const columns = ['date', 'title', 'requester', 'items', 'status', 'issued', 'returned', 'outstanding', 'state'];
            return Column(children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton(onPressed: () => _pick(true), child: Text('From ${_date(from)}')),
                OutlinedButton(onPressed: () => _pick(false), child: Text('To ${_date(to)}')),
                IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load())),
              ]),
              Padding(padding: const EdgeInsets.all(8), child: Text('${rows.length} requests, $outstanding outstanding')),
              Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: DataTable(
                columns: [for (final c in columns) DataColumn(label: Text(c))],
                rows: [for (final row in rows) DataRow(cells: [for (final c in columns) DataCell(Text('${row[c] ?? ''}'))])],
              )))),
              Padding(padding: const EdgeInsets.all(8), child: FilledButton.icon(
                onPressed: () => downloadText('equipment-requests-${_date(from)}-${_date(to)}.csv', reportCsv(rows), 'text/csv'),
                icon: const Icon(Icons.download), label: const Text('Download CSV'),
              )),
            ]);
          },
        ),
      );
}
