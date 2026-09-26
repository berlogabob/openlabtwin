// Places: the storage tree (rooms, cabinets, shelves, boxes), each place's contents, and the stocktake.
// A place's code is on its QR label (office/?place=CODE) and is the node name in the Godot twin: keep it once printed.
import 'package:flutter/material.dart';

import 'bookings.dart';
import 'data.dart';
import 'inventory.dart';
import 'logic.dart';

String _day(Object? at) => at == null ? 'never counted' : 'counted ${isoDate(DateTime.parse(at as String).toLocal())}';

/// Add a place (parent given) or edit one. Returns the saved row.
Future<Rec?> editPlace(BuildContext context, Refs refs, {Rec? place, int? parentId}) async {
  final name = TextEditingController(text: place?['name'] as String? ?? '');
  final code = TextEditingController(text: place?['code'] as String? ?? '');
  var tier = place?['tier'] as String? ?? 'fast';
  int? parent = place == null ? parentId : place['parent_id'] as int?;
  final isRoom = place?['kind'] == 'room';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: Text(place == null ? 'Add place' : 'Edit place'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (e.g. Rack 1, shelf 2)'),
              ),
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Code (e.g. B2-R1-S2)',
                  helperText: place?['code'] == null ? null : 'Changing it breaks printed labels and the Godot link.',
                ),
              ),
              if (!isRoom)
                DropdownButton<String>(
                  value: tier,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'fast', child: Text('fast (everyday storage)')),
                    DropdownMenuItem(value: 'long', child: Text('long (-2 floor, long-term)')),
                  ],
                  onChanged: (v) => set(() => tier = v!),
                ),
              DropdownButton<int?>(
                value: parent,
                isExpanded: true,
                hint: const Text('Inside (none: top level)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Top level')),
                  for (final (p, depth) in placeTree(refs.places))
                    if (p['id'] != place?['id'])
                      DropdownMenuItem(value: p['id'] as int, child: Text('${'  ' * depth}${refs.placeName(p['id'] as int)}')),
                ],
                onChanged: (v) => set(() => parent = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final c = code.text.trim().toUpperCase();
  if (name.text.trim().isEmpty) {
    say(context, 'Give the place a name.');
    return null;
  }
  if (c.isNotEmpty && !validCode(c)) {
    say(context, 'A code is capitals, digits and dashes, like B2-R1-S2.');
    return null;
  }
  try {
    final saved = await savePlace({
      'name': name.text.trim(),
      'code': c.isEmpty ? null : c,
      'parent_id': parent,
      if (!isRoom) ...{'kind': 'storage', 'tier': tier},
    }, place?['id'] as int?);
    refs.places
      ..removeWhere((p) => p['id'] == saved['id'])
      ..add(saved);
    return saved;
  } catch (e) {
    if (context.mounted) say(context, 'Could not save: $e');
    return null;
  }
}

class PlacesPage extends StatefulWidget {
  const PlacesPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  late final refs = widget.refs;
  late Future<List<Rec>> data = stock();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Places')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        if (await editPlace(context, refs) != null) setState(() => data = stock());
      },
      icon: const Icon(Icons.add),
      label: const Text('Add place'),
    ),
    body: FutureBuilder(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        final rows = snap.data;
        if (rows == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          children: [
            for (final (p, depth) in placeTree(refs.places))
              ListTile(
                contentPadding: EdgeInsets.only(left: 16.0 + 20 * depth, right: 16),
                title: Text(refs.placeName(p['id'] as int)),
                subtitle: Text(
                  [
                    p['tier'] ?? p['kind'],
                    '${rows.where((s) => s['place_id'] == p['id'] && s['qty'] != 0).length} items',
                    _day(p['counted_at']),
                  ].join(' · '),
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlacePage(refs: refs, place: p),
                    ),
                  );
                  setState(() => data = stock());
                },
              ),
          ],
        );
      },
    ),
  );
}

/// One place: what should be here, the stocktake, and movements from here.
class PlacePage extends StatefulWidget {
  const PlacePage({super.key, required this.refs, required this.place});
  final Refs refs;
  final Rec place;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  late final refs = widget.refs;
  late Rec place = widget.place;
  late Future<(List<Rec>, List<Rec>)> data = _load();
  bool counting = false;
  final counts = <int, TextEditingController>{};
  final seen = <int>{};

  int get id => place['id'] as int;

  Future<(List<Rec>, List<Rec>)> _load() async => (await stock(), await assetPlaces());

  void _reload() => setState(() {
    data = _load();
    counting = false;
  });

  /// Items here: total, and untagged = total minus the tagged ones that are here.
  (Map<int, num>, Map<int, num>, List<Rec>) _here(List<Rec> stockRows, List<Rec> where) {
    final total = {
      for (final s in stockRows)
        if (s['place_id'] == id && s['qty'] != 0) s['item_id'] as int: s['qty'] as num,
    };
    final hereIds = {
      for (final w in where)
        if (w['place_id'] == id) w['asset_id'],
    };
    final tagged = [
      for (final a in refs.assets)
        if (hereIds.contains(a['id'])) a,
    ];
    final untagged = {for (final e in total.entries) e.key: e.value - tagged.where((a) => a['item_id'] == e.key).length};
    return (total, untagged, tagged);
  }

  void _startCount(Map<int, num> untagged) => setState(() {
    counting = true;
    seen.clear();
    counts
      ..clear()
      ..addAll({for (final e in untagged.entries) e.key: TextEditingController(text: '${e.value}')});
  });

  Future<void> _saveCount(Map<int, num> untagged, List<Rec> tagged) async {
    final counted = <int, num>{};
    for (final e in counts.entries) {
      final n = num.tryParse(e.value.text.trim());
      if (n == null || n < 0) return say(context, 'Type a count (0 or more) for ${refs.itemNames[e.key]}.');
      counted[e.key] = n;
    }
    try {
      await addMovements(countAdjustments(untagged, counted, id, byStaff: refs.me));
      final now = DateTime.now().toUtc().toIso8601String();
      final found = [
        for (final a in tagged)
          if (seen.contains(a['id'])) a['id'] as int,
      ];
      final missing = [
        for (final a in tagged)
          if (!seen.contains(a['id'])) a['id'] as int,
      ];
      if (found.isNotEmpty) await updateAssets(found, {'seen_at': now, 'condition': 'ok'});
      if (missing.isNotEmpty) await updateAssets(missing, {'condition': 'missing'});
      for (final a in tagged) {
        a['condition'] = seen.contains(a['id']) ? 'ok' : 'missing';
      }
      await markCounted(id);
      place = {...place, 'counted_at': now};
      refs.places
        ..removeWhere((p) => p['id'] == id)
        ..add(place);
      if (mounted) say(context, 'Counted. ${missing.isEmpty ? '' : '${missing.length} tagged not found, marked missing.'}');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not save the count: $e');
    }
  }

  Future<void> _condition(Rec a) async {
    final c = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${a['tag']} is…'),
        children: [
          for (final c in const ['ok', 'broken', 'missing']) SimpleDialogOption(onPressed: () => Navigator.pop(context, c), child: Text(c)),
        ],
      ),
    );
    if (c == null) return;
    try {
      await updateAssets([a['id'] as int], {'condition': c});
      setState(() => a['condition'] = c);
    } catch (e) {
      if (mounted) say(context, 'Could not save: $e');
    }
  }

  Future<void> _tag() async {
    int? itemId;
    final tag = TextEditingController(), serial = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Tag an item here'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int?>(
                value: itemId,
                isExpanded: true,
                hint: const Text('Item'),
                items: [for (final i in refs.items) DropdownMenuItem(value: i['id'] as int, child: Text(i['name'] as String))],
                onChanged: (v) => set(() => itemId = v),
              ),
              TextField(
                controller: tag,
                decoration: const InputDecoration(labelText: 'Tag (empty: next TL number)'),
              ),
              TextField(
                controller: serial,
                decoration: const InputDecoration(labelText: 'Serial number (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tag it')),
          ],
        ),
      ),
    );
    if (ok != true || itemId == null) return;
    try {
      // a new tag for something already counted here: the tag is received, and the untagged count drops by one
      final a = await addAsset(itemId!, tag.text.toUpperCase(), serial.text);
      await addMovements([
        movementRow(kind: 'receive', itemId: itemId!, qty: 1, to: id, assetId: a['id'] as int, byStaff: refs.me, note: 'tagged'),
        movementRow(kind: 'adjust', itemId: itemId!, qty: -1, to: id, byStaff: refs.me, note: 'tagged'),
      ]);
      refs.assets.add(a);
      if (mounted) say(context, 'Tagged ${a['tag']}. Print its label with scripts/labels.py --assets.');
      _reload();
    } catch (e) {
      if (mounted) say(context, 'Could not tag: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = place['parent_id'] == null ? null : refs.placeName(place['parent_id'] as int);
    return Scaffold(
      appBar: AppBar(
        // opened from a QR label: nothing to go back to, so offer the office instead
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                tooltip: 'Office',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const BookingsPage())),
              ),
        title: Text(refs.placeName(id)),
        actions: [
          IconButton(
            tooltip: 'Edit place',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await editPlace(context, refs, place: place);
              if (saved != null) setState(() => place = saved);
            },
          ),
          IconButton(
            tooltip: 'Add a place inside',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => editPlace(context, refs, parentId: id),
          ),
          IconButton(tooltip: 'Tag an item', icon: const Icon(Icons.qr_code_2), onPressed: _tag),
        ],
      ),
      floatingActionButton: counting
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                if (await recordMovement(context, refs, placeId: id)) _reload();
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Record movement'),
            ),
      body: FutureBuilder(
        future: data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
          final loaded = snap.data;
          if (loaded == null) return const Center(child: CircularProgressIndicator());
          final (total, untagged, tagged) = _here(loaded.$1, loaded.$2);
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              ListTile(
                title: Text([if (parent != null) 'in $parent', place['tier'] ?? place['kind'], _day(place['counted_at'])].join(' · ')),
                trailing: counting
                    ? Wrap(
                        spacing: 8,
                        children: [
                          TextButton(onPressed: () => setState(() => counting = false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => _saveCount(untagged, tagged), child: const Text('Save count')),
                        ],
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _startCount(untagged),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Count'),
                      ),
              ),
              if (counting)
                const ListTile(
                  dense: true,
                  title: Text('Type what is really here. Tick each tagged item you see; unticked ones are marked missing.'),
                ),
              if (total.isEmpty && !counting) const ListTile(title: Text('Nothing recorded here.')),
              for (final e in (counting ? untagged : total).entries)
                ListTile(
                  title: Text(refs.itemNames[e.key] ?? 'item ${e.key}'),
                  subtitle: counting || untagged[e.key] == e.value ? null : Text('${untagged[e.key]} untagged'),
                  trailing: counting
                      ? SizedBox(
                          width: 80,
                          child: Semantics(
                            label: 'Count of ${refs.itemNames[e.key] ?? 'item ${e.key}'}',
                            child: TextField(
                              controller: counts[e.key],
                              textAlign: TextAlign.end,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        )
                      : Text('${e.value}', style: Theme.of(context).textTheme.titleMedium),
                ),
              if (tagged.isNotEmpty) const ListTile(dense: true, title: Text('Tagged')),
              for (final a in tagged)
                counting
                    ? CheckboxListTile(
                        value: seen.contains(a['id']),
                        onChanged: (v) => setState(() => v! ? seen.add(a['id'] as int) : seen.remove(a['id'])),
                        title: Text('${a['tag']} · ${refs.itemNames[a['item_id']]}'),
                        subtitle: a['serial'] == null ? null : Text('${a['serial']}'),
                      )
                    : ListTile(
                        title: Text('${a['tag']} · ${refs.itemNames[a['item_id']]}'),
                        subtitle: Text([if (a['serial'] != null) a['serial'], a['condition']].join(' · ')),
                        trailing: a['condition'] == 'ok' ? null : const Icon(Icons.error_outline, color: Colors.orange),
                        onTap: () => _condition(a),
                      ),
            ],
          );
        },
      ),
    );
  }
}

/// The screen a QR label opens (office/?place=CODE), once refs are loaded.
class PlaceLinkPage extends StatelessWidget {
  const PlaceLinkPage({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: loadRefs(),
    builder: (context, snap) {
      if (snap.hasError) return Scaffold(body: Center(child: Text('Could not load: ${snap.error}')));
      final refs = snap.data;
      if (refs == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final p = refs.placeByCode(code.toUpperCase());
      return p == null ? const BookingsPage() : PlacePage(refs: refs, place: p);
    },
  );
}
