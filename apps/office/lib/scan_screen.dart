import 'package:material_ui/material_ui.dart';

import 'bookings.dart';
import 'data.dart';
import 'places.dart';
import 'scan_logic.dart';
import 'scan_widget.dart';

class ScanButton extends StatelessWidget {
  const ScanButton({super.key, this.refs});
  final Refs? refs;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Scan',
    icon: const Icon(Icons.qr_code_scanner),
    onPressed: () async {
      try {
        final loaded = refs ?? await loadRefs();
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ScanPage(refs: loaded)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Could not load: $e')));
        }
      }
    },
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.refs, this.camera = true});
  final Refs refs;
  final bool camera;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String? unknown;
  final search = TextEditingController();
  bool opening = false;

  Future<void> _code(String code) async {
    if (opening) return;
    final result = resolveCode(code, widget.refs.places, widget.refs.assets);
    if (result.kind == ScanKind.unknown) {
      setState(() {
        unknown = result.code;
        search.text = result.code;
      });
      return;
    }
    setState(() => unknown = null);
    opening = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => result.kind == ScanKind.place
            ? PlacePage(refs: widget.refs, place: result.row!)
            : AssetPage(refs: widget.refs, asset: result.row!),
      ),
    );
    opening = false;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    bool matches(Object? value) =>
        value != null && value.toString().toLowerCase().contains(query);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CodeCapture(onCode: _code, camera: widget.camera),
          if (unknown != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Not in the catalogue: $unknown'),
                    const Text(
                      'To add it: open the place it is in and use Tag an item (QR icon), typing this code.',
                    ),
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: 'Search items and places',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (query.isNotEmpty) ...[
                      for (final item in widget.refs.items.where(
                        (i) => matches(i['name']),
                      ))
                        ListTile(
                          title: Text(item['name'] as String),
                          subtitle: const Text('Item'),
                        ),
                      for (final place in widget.refs.places.where(
                        (p) => matches(p['name']) || matches(p['code']),
                      ))
                        ListTile(
                          title: Text(
                            widget.refs.placeName(place['id'] as int),
                          ),
                          subtitle: const Text('Place'),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PlacePage(refs: widget.refs, place: place),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AssetPage extends StatefulWidget {
  const AssetPage({
    super.key,
    required this.refs,
    required this.asset,
    this.loadPlaces,
    this.loadHistory,
  });
  final Refs refs;
  final Rec asset;
  final Future<List<Rec>> Function()? loadPlaces, loadHistory;

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  late final Future<(List<Rec>, List<Rec>)> data = _load();
  Future<(List<Rec>, List<Rec>)> _load() async => (
    await (widget.loadPlaces ?? assetPlaces)(),
    await (widget.loadHistory ??
        () => assetHistory(widget.asset['id'] as int))(),
  );

  String person(int? id) =>
      widget.refs.people.where((p) => p['id'] == id).firstOrNull?['name']
          as String? ??
      '?';

  @override
  Widget build(BuildContext context) {
    final refs = widget.refs;
    final asset = widget.asset;
    return Scaffold(
      appBar: AppBar(title: Text(asset['tag'] as String? ?? 'Asset')),
      body: FutureBuilder(
        future: data,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (places, history) = snap.data!;
          final location = places
              .where((p) => p['asset_id'] == asset['id'])
              .firstOrNull;
          final place = refs.places
              .where((p) => p['id'] == location?['place_id'])
              .firstOrNull;
          final personId = location?['person_id'] as int?;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Tag: ${asset['tag'] ?? '—'}'),
              Text('Item: ${refs.itemNames[asset['item_id']] ?? '?'}'),
              Text('Serial: ${asset['serial'] ?? '—'}'),
              Text('Condition: ${asset['condition'] ?? '—'}'),
              const SizedBox(height: 16),
              Text(
                'Where it is now',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (place != null)
                ListTile(
                  title: Text(refs.placeName(place['id'] as int)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlacePage(refs: refs, place: place),
                    ),
                  ),
                )
              else
                Text(
                  personId == null
                      ? 'Nowhere recorded'
                      : 'Held by ${person(personId)}',
                ),
              const SizedBox(height: 16),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              if (history.isEmpty) const Text('No movements recorded.'),
              for (final row in history)
                ListTile(
                  title: Text(
                    '${row['at'] == null ? '?' : DateTime.parse(row['at'] as String).toLocal().toString().substring(0, 16)} · ${row['kind']}',
                  ),
                  subtitle: Text(
                    '${row['from_place'] != null
                        ? refs.placeName(row['from_place'] as int)
                        : row['kind'] == 'return' && row['person_id'] != null
                        ? person(row['person_id'] as int)
                        : '—'} → ${row['to_place'] != null
                        ? refs.placeName(row['to_place'] as int)
                        : row['person_id'] != null
                        ? person(row['person_id'] as int)
                        : '—'}${row['note'] == null ? '' : '\n${row['note']}'}',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AssetLinkPage extends StatelessWidget {
  const AssetLinkPage({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: loadRefs(),
    builder: (context, snap) {
      if (snap.hasError) {
        return Scaffold(
          body: Center(child: Text('Could not load: ${snap.error}')),
        );
      }
      final refs = snap.data;
      if (refs == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final result = resolveCode(
        Uri(queryParameters: {'asset': tag}).toString(),
        refs.places,
        refs.assets,
      );
      return result.kind == ScanKind.asset
          ? AssetPage(refs: refs, asset: result.row!)
          : const BookingsPage();
    },
  );
}
