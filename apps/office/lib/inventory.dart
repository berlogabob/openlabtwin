// Inventory: Needs attention, stock per place, who holds what, and one form for every movement.
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';
import 'places.dart';
import 'archive_screen.dart';
import 'usage_screen.dart';
import 'pick.dart';

void say(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The Record movement form. `placeId` prefills From or To (a place's own screen). True when something was recorded.
Future<bool> recordMovement(BuildContext context, Refs refs, {int? placeId}) async {
  var kind = 'receive';
  int? itemId, assetId, from = placeId, to = placeId, personId;
  final qty = TextEditingController(text: '1');
  final newName = TextEditingController();
  var newKind = 'portable';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        Pick<int?> placePick(String label, int? value, void Function(int?) change) => Pick<int?>(
              label: label,
              value: value,
              options: [for (final (p, _) in placeTree(refs.places)) (p['id'] as int, refs.placeName(p['id'] as int))],
              onChanged: (v) => set(() => change(v)),
            );
        final tagged = [
          for (final a in refs.assets)
            if (a['item_id'] == itemId) a,
        ];
        return AlertDialog(
          title: const Text('Record movement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: kind,
                  isExpanded: true,
                  items: [for (final k in movementKinds) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => set(() => kind = v!),
                ),
                Pick<int?>(
                  label: 'Item, or type a new one below',
                  value: itemId,
                  options: [for (final i in refs.items) (i['id'] as int, '${i['name']} (${i['kind']})')],
                  onChanged: (v) => set(() => (itemId, assetId) = (v, null)),
                ),
                if (itemId == null) ...[
                  TextField(
                    controller: newName,
                    decoration: const InputDecoration(labelText: 'New item name'),
                  ),
                  DropdownButton<String>(
                    value: newKind,
                    isExpanded: true,
                    items: [
                      for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) => set(() => newKind = v!),
                  ),
                ],
                if (tagged.isNotEmpty)
                  Pick<int?>(
                    label: 'Tagged one (optional)',
                    value: assetId,
                    nullText: 'Untagged',
                    options: [for (final a in tagged) (a['id'] as int, '${a['tag']}${a['serial'] == null ? '' : ' · ${a['serial']}'}')],
                    onChanged: (v) => set(() {
                      assetId = v;
                      if (v != null) qty.text = kind == 'adjust' && qty.text.startsWith('-') ? '-1' : '1';
                    }),
                  ),
                TextField(
                  controller: qty,
                  decoration: InputDecoration(labelText: kind == 'adjust' ? 'Correction (+/-)' : 'Quantity'),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                ),
                if (const {'move', 'issue', 'consume'}.contains(kind)) placePick('From', from, (v) => from = v),
                if (const {'receive', 'move', 'return', 'adjust'}.contains(kind))
                  placePick(kind == 'adjust' ? 'Place' : 'To', to, (v) => to = v),
                if (const {'issue', 'return'}.contains(kind))
                  Pick<int?>(
                    label: kind == 'issue' ? 'Given to' : 'Returned by',
                    value: personId,
                    options: [for (final p in refs.people) (p['id'] as int, '${p['name']} (${p['kind']})')],
                    onChanged: (v) => set(() => personId = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    if (itemId == null) {
      if (newName.text.trim().isEmpty) {
        say(context, 'Pick an item or type a new one.');
        return false;
      }
      final item = await addItem(newName.text, newKind);
      refs.items.add(item);
      itemId = item['id'] as int;
    }
    final row = movementRow(
      kind: kind,
      itemId: itemId!,
      qty: num.tryParse(qty.text.trim()) ?? 0,
      from: from,
      to: to,
      personId: personId,
      byStaff: refs.me,
      assetId: assetId,
    );
    await addMovements([row]);
    if (context.mounted) say(context, 'Recorded: $kind ${row['qty']} × ${refs.itemNames[itemId]}.');
    return true;
  } on ArgumentError catch (e) {
    if (context.mounted) say(context, e.message as String);
  } catch (e) {
    if (context.mounted) say(context, 'Could not record: $e');
  }
  return false;
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final refs = widget.refs;
  late Future<(List<Rec>, List<Rec>, List<Rec>)> data = _load();
  bool showGone = false;

  Future<(List<Rec>, List<Rec>, List<Rec>)> _load() async => (await stock(), await onLoan(), await storageIssues());

  String _person(int? id) => refs.people.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;

  void _reload() => setState(() => data = _load());

  Future<void> _merge(Rec issue) async {
    final a = issue['a_id'] as int, b = issue['b_id'] as int;
    final keep = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Same thing? Keep which name'),
        children: [
          for (final id in [a, b])
            SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text(refs.itemNames[id] ?? 'item $id')),
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

  /// An item's details: its note from the spreadsheet, and whether the public /kit/ list offers it.
  Future<void> _item(Rec i) async {
    var lendable = i['lendable'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(i['name'] as String),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i['note'] != null) Text(i['note'] as String),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Can be requested (public equipment list)'),
                value: lendable,
                onChanged: (v) => set(() => lendable = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || lendable == (i['lendable'] == true)) return;
    try {
      await setLendable(i['id'] as int, lendable);
      setState(() => i['lendable'] = lendable);
    } catch (e) {
      if (mounted) say(context, 'Could not save: $e');
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
              final p = refs.places.where((p) => p['id'] == i['a_id']).firstOrNull;
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
          if (code == 'possible_duplicate') TextButton(onPressed: () => _merge(i), child: const Text('Merge')),
          TextButton(onPressed: () => _waive(i), child: Text(code == 'possible_duplicate' ? 'Not the same' : 'Dismiss')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Inventory'),
      actions: [
        IconButton(
          tooltip: 'Archive',
          icon: const Icon(Icons.history_edu),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArchiveScreen(refs: refs))),
        ),
        IconButton(
          tooltip: 'Usage',
          icon: const Icon(Icons.insights),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UsageScreen(refs: refs))),
        ),
        IconButton(
          tooltip: 'Places',
          icon: const Icon(Icons.account_tree_outlined),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlacesPage(refs: refs)));
            _reload();
          },
        ),
        IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        if (await recordMovement(context, refs)) _reload();
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
        final (stockRows, loans, issues) = loaded;
        if (refs.items.isEmpty) return const Center(child: Text('No items yet. Record a "receive" to add the first one.'));
        final gone = refs.items.where((i) => isGone(i['id'] as int, stockRows, loans)).length;
        return ListView(
          children: [
            FilterChip(
              label: Text('Show items with nothing left ($gone)'),
              selected: showGone,
              onSelected: (v) => setState(() => showGone = v),
            ),
            if (issues.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: issues.length <= 10,
                leading: const Icon(Icons.warning_amber),
                title: Text('Needs attention (${issues.length})'),
                children: [for (final i in issues) _issue(i)],
              ),
            for (final i in refs.items)
              if (showGone || !isGone(i['id'] as int, stockRows, loans))
              Builder(
                builder: (context) {
                  final here = [
                    for (final s in stockRows)
                      if (s['item_id'] == i['id'] && s['qty'] != 0) s,
                  ];
                  final out = [
                    for (final l in loans)
                      if (l['item_id'] == i['id']) l,
                  ];
                  final total = here.fold<num>(0, (t, s) => t + (s['qty'] as num));
                  final tags = refs.assets.where((a) => a['item_id'] == i['id']).length;
                  return ListTile(
                    onTap: () => _item(i),
                    title: Text('${i['name']} (${i['kind']})${tags == 0 ? '' : ' · $tags tagged'}'
                        '${i['lendable'] == true ? ' · can be requested' : ''}'),
                    subtitle: Text(
                      [
                        for (final s in here) '${refs.placeName(s['place_id'] as int?)} ${s['qty']}',
                        for (final l in out) 'on loan: ${_person(l['person_id'] as int?)} ${l['qty']}',
                      ].join(' · '),
                    ),
                    trailing: Text('$total', style: Theme.of(context).textTheme.titleMedium),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}
