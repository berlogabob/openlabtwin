import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'data.dart';
import 'inventory.dart';
import 'logic.dart';
import 'pick.dart';
import 'scan_screen.dart';

typedef ItemRows = (List<Rec>, List<Rec>, List<Rec>, List<Rec>);

String movementWords(Rec row, Refs refs) {
  final person =
      refs.people
          .where((p) => p['id'] == row['person_id'])
          .firstOrNull?['name'] ??
      '?';
  final from = refs.placeName(row['from_place'] as int?);
  final to = refs.placeName(row['to_place'] as int?);
  return switch (row['kind']) {
    'issue' => 'Handed out to $person from $from',
    'return' => 'Taken back from $person to $to',
    'move' => 'Moved from $from to $to',
    'adjust' => 'Counted at $to (${row['qty']})',
    'receive' => 'Added to $to',
    'consume' => 'Used from $from',
    _ => 'Movement recorded',
  };
}

Future<bool> everydayMovement(
  BuildContext context,
  Refs refs,
  Rec item,
  String action, {
  Rec? asset,
  Rec? location,
  List<Rec> stockRows = const [],
  List<Rec> loans = const [],
  List<Rec> history = const [],
  Future<void> Function(List<Rec>)? save,
}) async {
  final available =
      stockRows
          .where((s) => s['item_id'] == item['id'] && (s['qty'] as num) > 0)
          .toList()
        ..sort((a, b) => (b['qty'] as num).compareTo(a['qty'] as num));
  int? from =
      location?['place_id'] as int? ??
      available.firstOrNull?['place_id'] as int?;
  int? to = action == 'Take back' && asset != null
      ? (history.where((h) => h['kind'] == 'issue').firstOrNull?['from_place']
            as int?)
      : null;
  int? person = location?['person_id'] as int?;
  final qty = TextEditingController(text: '1');
  var saving = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, set) {
        Pick<int?> placePick(
          String label,
          int? value,
          void Function(int?) change,
        ) => Pick<int?>(
          label: label,
          value: value,
          options: [
            for (final p in refs.places)
              (p['id'] as int, refs.placeName(p['id'] as int)),
          ],
          onChanged: (v) => set(() => change(v)),
        );
        return AlertDialog(
          title: Text(action),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action != 'Take back' && asset == null)
                  placePick('From', from, (v) => from = v),
                if (action == 'Hand out' ||
                    (action == 'Take back' && asset == null)) ...[
                  Pick<int?>(
                    label: action == 'Hand out' ? 'Person' : 'Holder',
                    value: person,
                    options: [
                      for (final p in refs.people)
                        if (action == 'Hand out' ||
                            loans.any(
                              (l) =>
                                  l['item_id'] == item['id'] &&
                                  l['person_id'] == p['id'] &&
                                  (l['qty'] as num) > 0,
                            ))
                          (p['id'] as int, '${p['name']}'),
                    ],
                    onChanged: (v) => set(() => person = v),
                  ),
                  if (action == 'Hand out')
                    TextButton(
                      onPressed: () async {
                        final name = TextEditingController(),
                            email = TextEditingController();
                        var kind = 'professor';
                        final ok = await showDialog<bool>(
                          context: dialog,
                          builder: (c) => StatefulBuilder(
                            builder: (c, update) => AlertDialog(
                              title: const Text('New person'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: name,
                                    decoration: const InputDecoration(
                                      labelText: 'Name',
                                    ),
                                  ),
                                  TextField(
                                    controller: email,
                                    decoration: const InputDecoration(
                                      labelText: 'Email (private)',
                                    ),
                                  ),
                                  DropdownButton<String>(
                                    value: kind,
                                    isExpanded: true,
                                    items: [
                                      for (final k in const [
                                        'professor',
                                        'student',
                                        'staff',
                                        'external',
                                      ])
                                        DropdownMenuItem(
                                          value: k,
                                          child: Text(k),
                                        ),
                                    ],
                                    onChanged: (v) => update(() => kind = v!),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Add'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (ok == true && name.text.trim().isNotEmpty) {
                          try {
                            final p = await addPerson(
                              name.text,
                              kind,
                              email.text,
                            );
                            refs.people.add(p);
                            set(() => person = p['id'] as int);
                          } catch (e) {
                            if (dialog.mounted) {
                              say(dialog, 'Could not add person: $e');
                            }
                          }
                        }
                      },
                      child: const Text('Add person'),
                    ),
                ],
                if (asset == null)
                  TextField(
                    controller: qty,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                if (action != 'Hand out') placePick('To', to, (v) => to = v),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      try {
                        final row = movementRow(
                          kind: action == 'Hand out'
                              ? 'issue'
                              : action == 'Take back'
                              ? 'return'
                              : 'move',
                          itemId: item['id'] as int,
                          qty: asset == null
                              ? num.tryParse(qty.text.trim()) ?? 0
                              : 1,
                          from: from,
                          to: to,
                          personId: person,
                          byStaff: refs.me,
                          assetId: asset?['id'] as int?,
                        );
                        set(() => saving = true);
                        await (save ?? addMovements)([row]);
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } on ArgumentError catch (e) {
                        if (dialog.mounted) say(context, '${e.message}');
                      } on PostgrestException catch (e) {
                        if (dialog.mounted) say(context, e.message);
                      } catch (e) {
                        if (dialog.mounted) say(context, 'Could not save: $e');
                      } finally {
                        if (dialog.mounted) set(() => saving = false);
                      }
                    },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    ),
  );
  if (result == true && context.mounted) {
    final name = asset?['tag'] ?? item['name'];
    final who =
        refs.people.where((p) => p['id'] == person).firstOrNull?['name'] ?? '?';
    say(
      context,
      action == 'Hand out'
          ? 'Handed out $name to $who'
          : action == 'Take back'
          ? 'Took back $name'
          : 'Moved $name',
    );
  }
  // qty is not disposed: the sheet still reads it during its closing animation.
  return result == true;
}

class ItemPage extends StatefulWidget {
  const ItemPage({
    super.key,
    required this.refs,
    required this.item,
    this.loader,
    this.save,
  });
  final Refs refs;
  final Rec item;
  final Future<ItemRows> Function()? loader;
  final Future<void> Function(List<Rec>)? save;
  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  late Future<ItemRows> data = load();
  Future<ItemRows> load() async => widget.loader == null
      ? (
          await stock(),
          await onLoan(),
          await assetPlaces(),
          await itemHistory(widget.item['id'] as int),
        )
      : widget.loader!();
  void reload() => setState(() {
    data = load();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.item['name']}')),
    body: FutureBuilder<ItemRows>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Could not load: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (stocks, loans, locations, history) = snap.data!;
        final item = widget.item, refs = widget.refs;
        final shelves = stocks
            .where((s) => s['item_id'] == item['id'] && s['qty'] != 0)
            .toList();
        final held = loans
            .where((l) => l['item_id'] == item['id'] && (l['qty'] as num) > 0)
            .toList();
        final units = refs.assets
            .where((a) => a['item_id'] == item['id'])
            .toList();
        final total =
            shelves.fold<num>(0, (n, s) => n + (s['qty'] as num)) +
            held.fold<num>(0, (n, s) => n + (s['qty'] as num));
        String person(Object? id) =>
            '${refs.people.where((p) => p['id'] == id).firstOrNull?['name'] ?? '?'}';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${item['kind'] ?? ''} · Total $total'),
            Wrap(
              spacing: 8,
              children: [
                for (final action in [
                  'Hand out',
                  if (held.isNotEmpty ||
                      locations.any(
                        (l) =>
                            l['person_id'] != null &&
                            units.any((a) => a['id'] == l['asset_id']),
                      ))
                    'Take back',
                  'Move',
                ])
                  FilledButton(
                    onPressed: () async {
                      if (await everydayMovement(
                        context,
                        refs,
                        item,
                        action,
                        stockRows: stocks,
                        loans: loans,
                        save: widget.save,
                      )) {
                        reload();
                      }
                    },
                    child: Text(action),
                  ),
              ],
            ),
            const ListTile(title: Text('Where')),
            for (final s in shelves)
              ListTile(
                title: Text(refs.placeName(s['place_id'] as int?)),
                trailing: Text('${s['qty']}'),
              ),
            const ListTile(title: Text('Out with')),
            for (final l in held)
              ListTile(
                title: Text(person(l['person_id'])),
                trailing: Text('${l['qty']}'),
              ),
            for (final a in units)
              if (locations.any(
                (l) => l['asset_id'] == a['id'] && l['person_id'] != null,
              ))
                ListTile(
                  title: Text(
                    '${a['tag']} · ${person(locations.firstWhere((l) => l['asset_id'] == a['id'])['person_id'])}',
                  ),
                ),
            const ListTile(title: Text('Units')),
            for (final a in units)
              ListTile(
                title: Text('${a['tag']}'),
                subtitle: Text(
                  '${a['serial'] ?? '—'} · ${a['condition'] ?? '—'} · ${() {
                    final l = locations.where((l) => l['asset_id'] == a['id']).firstOrNull;
                    return l?['person_id'] != null ? person(l!['person_id']) : refs.placeName(l?['place_id'] as int?);
                  }()}',
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AssetPage(refs: refs, asset: a),
                    ),
                  );
                  if (mounted) reload();
                },
              ),
            const ListTile(title: Text('History')),
            if (history.isEmpty)
              const ListTile(title: Text('No movements recorded.')),
            for (final h in history)
              ListTile(
                title: Text(movementWords(h, refs)),
                subtitle: Text('${h['at'] ?? ''}'),
              ),
            if (item['note'] != null) ListTile(title: Text('${item['note']}')),
            SwitchListTile(
              title: const Text('Can be requested (public equipment list)'),
              value: item['lendable'] == true,
              onChanged: (v) async {
                try {
                  await setLendable(item['id'] as int, v);
                  setState(() => item['lendable'] = v);
                } catch (e) {
                  if (context.mounted) say(context, 'Could not save: $e');
                }
              },
            ),
          ],
        );
      },
    ),
  );
}
