import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'item_page.dart';
import 'places.dart';
import 'scan_logic.dart';
import 'scan_screen.dart';
import 'storage_tools.dart';

typedef StorageRows = (List<Rec>, List<Rec>, List<Rec>);
Future<StorageRows> _load() async =>
    (await onLoan(), await assetPlaces(), await storageIssues());

String _fold(Object? value) {
  var s = (value ?? '').toString().toLowerCase();
  const groups = {
    'a': 'áàâãäå',
    'e': 'éèêë',
    'i': 'íìîï',
    'o': 'óòôõö',
    'u': 'úùûü',
    'c': 'ç',
    'n': 'ñ',
  };
  for (final e in groups.entries) {
    for (final c in e.value.split('')) {
      s = s.replaceAll(c, e.key);
    }
  }
  return s.replaceAll(RegExp(r'[\u0300-\u036f]'), '');
}

class StorageHome extends StatefulWidget {
  const StorageHome({super.key, required this.refs, this.loader});
  final Refs refs;
  final Future<StorageRows> Function()? loader;
  @override
  State<StorageHome> createState() => _StorageHomeState();
}

class _StorageHomeState extends State<StorageHome> {
  late Future<StorageRows> data = (widget.loader ?? _load)();
  String query = '';
  void reload() => setState(() {
    data = (widget.loader ?? _load)();
  });
  Future<void> openCode(String code) async {
    final result = resolveCode(code, widget.refs.places, widget.refs.assets);
    if (result.kind == ScanKind.unknown) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => result.kind == ScanKind.place
            ? PlacePage(refs: widget.refs, place: result.row!)
            : AssetPage(refs: widget.refs, asset: result.row!),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final refs = widget.refs;
    final q = _fold(query.trim());
    bool matches(Object? x) => _fold(x).contains(q);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (_) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => StorageTools(refs: refs),
                ),
              );
              if (mounted) reload();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'tools', child: Text('Tools')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<StorageRows>(
        future: data,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (loans, locations, issues) = snap.data!;
          final rows = <(int?, int?, String?, num, String?)>[
            for (final l in loans)
              if ((l['qty'] as num) -
                      locations
                          .where(
                            (w) =>
                                w['person_id'] == l['person_id'] &&
                                refs.assets.any(
                                  (a) =>
                                      a['id'] == w['asset_id'] &&
                                      a['item_id'] == l['item_id'],
                                ),
                          )
                          .length !=
                  0)
                (
                  l['person_id'] as int?,
                  l['item_id'] as int?,
                  null,
                  (l['qty'] as num) -
                      locations
                          .where(
                            (w) =>
                                w['person_id'] == l['person_id'] &&
                                refs.assets.any(
                                  (a) =>
                                      a['id'] == w['asset_id'] &&
                                      a['item_id'] == l['item_id'],
                                ),
                          )
                          .length,
                  null,
                ),
            for (final w in locations)
              if (w['person_id'] != null)
                for (final a in refs.assets)
                  if (a['id'] == w['asset_id'])
                    (
                      w['person_id'] as int?,
                      a['item_id'] as int?,
                      a['tag'] as String?,
                      1,
                      w['at'] as String?,
                    ),
          ];
          rows.sort((a, b) {
            if (a.$3 != null && b.$3 == null) return -1;
            if (a.$3 == null && b.$3 != null) return 1;
            if (a.$3 != null) return (b.$5 ?? '').compareTo(a.$5 ?? '');
            return (refs.itemNames[a.$2] ?? '').compareTo(
              refs.itemNames[b.$2] ?? '',
            );
          });
          Future<void> openItem(int? id) async {
            final item = refs.items.where((i) => i['id'] == id).firstOrNull;
            if (item == null) return;
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ItemPage(refs: refs, item: item),
              ),
            );
            if (mounted) reload();
          }

          String person(int? id) =>
              refs.people
                  .where((p) => p['id'] == id)
                  .firstOrNull?['name']
                  ?.toString() ??
              '?';
          Widget row((int?, int?, String?, num, String?) r) => ListTile(
            onTap: () => openItem(r.$2),
            title: Text(
              '${person(r.$1)} · ${refs.itemNames[r.$2] ?? '?'}${r.$3 == null ? ' · ${r.$4}' : ' · ${r.$3}'}',
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Find an item, tag, place or person',
                  suffixIcon: ScanButton(refs: refs),
                ),
                onChanged: (v) => setState(() => query = v),
                onSubmitted: openCode,
              ),
              if (q.isEmpty) ...[
                const ListTile(title: Text('Out now')),
                for (final r in rows) row(r),
                if (rows.isEmpty)
                  const ListTile(title: Text('Nothing out now.')),
                ListTile(
                  title: Text('Needs attention (${issues.length})'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => NeedsAttentionPage(
                          refs: refs,
                          loader: widget.loader == null
                              ? null
                              : () async => (await widget.loader!()).$3,
                        ),
                      ),
                    );
                    if (mounted) reload();
                  },
                ),
              ] else ...[
                const ListTile(title: Text('Items')),
                for (final i in refs.items.where((i) => matches(i['name'])))
                  ListTile(
                    title: Text('${i['name']}'),
                    onTap: () => openItem(i['id'] as int),
                  ),
                const ListTile(title: Text('Tagged units')),
                for (final a in refs.assets.where(
                  (a) => matches(a['tag']) || matches(a['serial']),
                ))
                  ListTile(
                    title: Text('${a['tag']}'),
                    subtitle: Text(
                      '${a['serial'] ?? ''} · ${refs.itemNames[a['item_id']] ?? '?'}',
                    ),
                    onTap: () => openCode('${a['tag']}'),
                  ),
                const ListTile(title: Text('Places')),
                for (final p in refs.places.where(
                  (p) => matches(p['code']) || matches(p['name']),
                ))
                  ListTile(
                    title: Text(refs.placeName(p['id'] as int)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlacePage(refs: refs, place: p),
                      ),
                    ),
                  ),
                const ListTile(title: Text('People')),
                for (final p in refs.people.where((p) => matches(p['name'])))
                  ListTile(
                    title: Text('${p['name']}'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text('${p['name']}')),
                          body: ListView(
                            children: [
                              for (final r in rows.where(
                                (r) => r.$1 == p['id'],
                              ))
                                row(r),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
