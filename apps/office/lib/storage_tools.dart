import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'inventory.dart';
import 'places.dart';
import 'pairing_screen.dart';
import 'archive_screen.dart';
import 'usage_screen.dart';

class StorageTools extends StatelessWidget {
  const StorageTools({super.key, required this.refs});
  final Refs refs;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tools')),
    body: ListView(
      children: [
        ListTile(
          title: const Text('Record movement'),
          onTap: () => recordMovement(context, refs),
        ),
        ListTile(
          title: const Text('Needs attention'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => NeedsAttentionPage(refs: refs),
            ),
          ),
        ),
        ListTile(
          title: const Text('Places'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => PlacesPage(refs: refs)),
          ),
        ),
        ListTile(
          title: const Text('Pair boxes and consoles'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const PairingPage()),
          ),
        ),
        ListTile(
          title: const Text('Archive'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => ArchiveScreen(refs: refs)),
          ),
        ),
        ListTile(
          title: const Text('Usage'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => UsageScreen(refs: refs)),
          ),
        ),
      ],
    ),
  );
}

class NeedsAttentionPage extends StatefulWidget {
  const NeedsAttentionPage({super.key, required this.refs, this.loader});
  final Refs refs;
  final Future<List<Rec>> Function()? loader;
  @override
  State<NeedsAttentionPage> createState() => _NeedsAttentionPageState();
}

class _NeedsAttentionPageState extends State<NeedsAttentionPage> {
  late final refs = widget.refs;
  late Future<List<Rec>> data = (widget.loader ?? storageIssues)();
  void _reload() => setState(() {
    data = (widget.loader ?? storageIssues)();
  });
  Future<void> _merge(Rec issue) async {
    final a = issue['a_id'] as int, b = issue['b_id'] as int;
    final keep = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Same thing? Keep which name'),
        children: [
          for (final id in [a, b])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, id),
              child: Text(refs.itemNames[id] ?? 'item $id'),
            ),
        ],
      ),
    );
    if (keep == null) return;
    try {
      await mergeItems(keep, [keep == a ? b : a]);
      refs.items.removeWhere((i) => i['id'] == (keep == a ? b : a));
      for (final x in refs.assets) {
        if (x['item_id'] == (keep == a ? b : a)) x['item_id'] = keep;
      }
      if (mounted) say(context, 'Merged into ${refs.itemNames[keep]}.');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not merge: $e');
    }
  }

  Future<void> _waive(Rec issue) async {
    try {
      await waiveIssue(issue['key'] as String, refs.me);
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not dismiss: $e');
    }
  }

  Widget _issue(Rec i) {
    final code = i['code'] as String;
    final placeIssue = code == 'never_counted' || code == 'stale_count';
    return ListTile(
      dense: true,
      leading: const Icon(Icons.error_outline, color: Colors.orange),
      title: Text(i['detail'] as String),
      subtitle: Text(code.replaceAll('_', ' ')),
      onTap: placeIssue
          ? () async {
              final p = refs.places
                  .where((p) => p['id'] == i['a_id'])
                  .firstOrNull;
              if (p == null) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlacePage(refs: refs, place: p),
                ),
              );
              _reload();
            }
          : null,
      trailing: Wrap(
        children: [
          if (code == 'possible_duplicate')
            TextButton(onPressed: () => _merge(i), child: const Text('Merge')),
          TextButton(
            onPressed: () => _waive(i),
            child: Text(
              code == 'possible_duplicate' ? 'Not the same' : 'Dismiss',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Needs attention')),
    body: FutureBuilder<List<Rec>>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Could not load: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.data!.isEmpty) {
          return const Center(child: Text('Nothing needs attention.'));
        }
        return ListView(children: [for (final i in snap.data!) _issue(i)]);
      },
    ),
  );
}
