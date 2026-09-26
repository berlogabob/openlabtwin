// Usage for the thesis and for buying: the archive and live loans together (views usage_by_item, usage_by_course, peak_on_loan).
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key, required this.refs});
  final Refs refs;

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  late Future<(List<Rec>, List<Rec>, List<Rec>)> data = _load();
  Future<(List<Rec>, List<Rec>, List<Rec>)> _load() async => (await usageByItem(), await usageByCourse(), await peakOnLoan());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Usage'), actions: [IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load()))]),
        body: FutureBuilder<(List<Rec>, List<Rec>, List<Rec>)>(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final loaded = snap.data;
            if (loaded == null) return const Center(child: CircularProgressIndicator());
            final (items, courses, peaks) = loaded;
            return ListView(padding: const EdgeInsets.all(16), children: [
              _title('Used most'),
              for (final r in topItems(items)) ListTile(title: Text(r.name), trailing: Text('${r.units}'), subtitle: Text('archive ${r.archive} · live ${r.live}')),
              _title('Ran out: buy more?'),
              for (final r in buyList(peaks)) ListTile(title: Text(r['name'] as String), subtitle: Text('peak out at once: ${r['peak']}'), trailing: Text('owned ${r['owned']}')),
              _title('By course'),
              for (final r in ([...courses]..sort((a, b) => (b['units'] as num).compareTo(a['units'] as num))).take(20))
                ListTile(title: Text('${r['course']} · ${r['name']}'), trailing: Text('${r['units']}')),
            ]);
          },
        ),
      );

  Widget _title(String text) => Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(text, style: Theme.of(context).textTheme.titleLarge));
}
