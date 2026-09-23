// Inventory: stock per place (fast/long storage, rooms), who holds what, and one form for every movement.
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  late final refs = widget.refs;
  late Future<(List<Rec>, List<Rec>)> data = _load();

  Future<(List<Rec>, List<Rec>)> _load() async => (await stock(), await onLoan());

  String _place(int? id) => refs.places.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;
  String _person(int? id) => refs.people.firstWhere((p) => p['id'] == id, orElse: () => {'name': '?'})['name'] as String;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _movement() async {
    var kind = 'receive';
    int? itemId, from, to, personId;
    final qty = TextEditingController(text: '1');
    final newName = TextEditingController();
    var newKind = 'portable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, set) {
        DropdownButton<int?> placePick(String hint, int? value, void Function(int?) change) => DropdownButton<int?>(
              value: value,
              isExpanded: true,
              hint: Text(hint),
              items: [
                for (final p in refs.places)
                  DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}${p['tier'] == null ? '' : ' (${p['tier']})'}')),
              ],
              onChanged: (v) => set(() => change(v)),
            );
        return AlertDialog(
          title: const Text('Record movement'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                value: kind,
                isExpanded: true,
                items: [for (final k in movementKinds) DropdownMenuItem(value: k, child: Text(k))],
                onChanged: (v) => set(() => kind = v!),
              ),
              DropdownButton<int?>(
                value: itemId,
                isExpanded: true,
                hint: const Text('Item, or type a new one below'),
                items: [for (final i in refs.items) DropdownMenuItem(value: i['id'] as int, child: Text('${i['name']} (${i['kind']})'))],
                onChanged: (v) => set(() => itemId = v),
              ),
              if (itemId == null) ...[
                TextField(controller: newName, decoration: const InputDecoration(labelText: 'New item name')),
                DropdownButton<String>(
                  value: newKind,
                  isExpanded: true,
                  items: [for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k))],
                  onChanged: (v) => set(() => newKind = v!),
                ),
              ],
              TextField(
                controller: qty,
                decoration: InputDecoration(labelText: kind == 'adjust' ? 'Correction (+/-)' : 'Quantity'),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              ),
              if (const {'move', 'issue', 'consume'}.contains(kind)) placePick('From', from, (v) => from = v),
              if (const {'receive', 'move', 'return', 'adjust'}.contains(kind)) placePick(kind == 'adjust' ? 'Place' : 'To', to, (v) => to = v),
              if (const {'issue', 'return'}.contains(kind))
                DropdownButton<int?>(
                  value: personId,
                  isExpanded: true,
                  hint: Text(kind == 'issue' ? 'Given to' : 'Returned by'),
                  items: [for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (${p['kind']})'))],
                  onChanged: (v) => set(() => personId = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      if (itemId == null) {
        if (newName.text.trim().isEmpty) return _say('Pick an item or type a new one.');
        final item = await addItem(newName.text, newKind);
        refs.items.add(item);
        itemId = item['id'] as int;
      }
      final row = movementRow(
          kind: kind, itemId: itemId!, qty: num.tryParse(qty.text.trim()) ?? 0, from: from, to: to, personId: personId, byStaff: refs.me);
      await addMovements([row]);
      _say('Recorded: $kind ${row['qty']} × ${refs.itemNames[itemId]}.');
      setState(() => data = _load());
    } on ArgumentError catch (e) {
      _say(e.message as String);
    } catch (e) {
      _say('Could not record: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Inventory'), actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load())),
        ]),
        floatingActionButton:
            FloatingActionButton.extended(onPressed: _movement, icon: const Icon(Icons.swap_horiz), label: const Text('Record movement')),
        body: FutureBuilder(
          future: data,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final loaded = snap.data;
            if (loaded == null) return const Center(child: CircularProgressIndicator());
            final (stockRows, loans) = loaded;
            if (refs.items.isEmpty) return const Center(child: Text('No items yet. Record a "receive" to add the first one.'));
            return ListView(children: [
              for (final i in refs.items)
                Builder(builder: (context) {
                  final here = [for (final s in stockRows) if (s['item_id'] == i['id'] && s['qty'] != 0) s];
                  final out = [for (final l in loans) if (l['item_id'] == i['id']) l];
                  final total = here.fold<num>(0, (t, s) => t + (s['qty'] as num));
                  return ListTile(
                    title: Text('${i['name']} (${i['kind']})'),
                    subtitle: Text([
                      for (final s in here) '${_place(s['place_id'] as int?)} ${s['qty']}',
                      for (final l in out) 'on loan: ${_person(l['person_id'] as int?)} ${l['qty']}',
                    ].join(' · ')),
                    trailing: Text('$total', style: Theme.of(context).textTheme.titleMedium),
                  );
                }),
            ]);
          },
        ),
      );
}
