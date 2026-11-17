// Inventory: Needs attention, stock per place, who holds what, and one form for every movement.
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'logic.dart';
import 'pick.dart';

void say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// The Record movement form. `placeId` prefills From or To (a place's own screen). True when something was recorded.
Future<bool> recordMovement(
  BuildContext context,
  Refs refs, {
  int? placeId,
}) async {
  var kind = 'receive';
  int? itemId, assetId, from = placeId, to = placeId, personId;
  final qty = TextEditingController(text: '1');
  final newName = TextEditingController();
  var newKind = 'portable';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) {
        Pick<int?> placePick(
          String label,
          int? value,
          void Function(int?) change,
        ) => Pick<int?>(
          label: label,
          value: value,
          options: [
            for (final (p, _) in placeTree(refs.places))
              (p['id'] as int, refs.placeName(p['id'] as int)),
          ],
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
                  items: [
                    for (final k in movementKinds)
                      DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) => set(() => kind = v!),
                ),
                Pick<int?>(
                  label: 'Item, or type a new one below',
                  value: itemId,
                  options: [
                    for (final i in refs.items)
                      (i['id'] as int, '${i['name']} (${i['kind']})'),
                  ],
                  onChanged: (v) => set(() => (itemId, assetId) = (v, null)),
                ),
                if (itemId == null) ...[
                  TextField(
                    controller: newName,
                    decoration: const InputDecoration(
                      labelText: 'New item name',
                    ),
                  ),
                  DropdownButton<String>(
                    value: newKind,
                    isExpanded: true,
                    items: [
                      for (final k in const [
                        'portable',
                        'consumable',
                        'stationary',
                      ])
                        DropdownMenuItem(value: k, child: Text(k)),
                    ],
                    onChanged: (v) => set(() => newKind = v!),
                  ),
                ],
                if (tagged.isNotEmpty)
                  Pick<int?>(
                    label: 'Tagged one (optional)',
                    value: assetId,
                    nullText: 'Untagged',
                    options: [
                      for (final a in tagged)
                        (
                          a['id'] as int,
                          '${a['tag']}${a['serial'] == null ? '' : ' · ${a['serial']}'}',
                        ),
                    ],
                    onChanged: (v) => set(() {
                      assetId = v;
                      if (v != null) {
                        qty.text = kind == 'adjust' && qty.text.startsWith('-')
                            ? '-1'
                            : '1';
                      }
                    }),
                  ),
                TextField(
                  controller: qty,
                  decoration: InputDecoration(
                    labelText: kind == 'adjust'
                        ? 'Correction (+/-)'
                        : 'Quantity',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),
                if (const {'move', 'issue', 'consume'}.contains(kind))
                  placePick('From', from, (v) => from = v),
                if (const {
                  'receive',
                  'move',
                  'return',
                  'adjust',
                }.contains(kind))
                  placePick(
                    kind == 'adjust' ? 'Place' : 'To',
                    to,
                    (v) => to = v,
                  ),
                if (const {'issue', 'return'}.contains(kind))
                  Pick<int?>(
                    label: kind == 'issue' ? 'Given to' : 'Returned by',
                    value: personId,
                    options: [
                      for (final p in refs.people)
                        (p['id'] as int, '${p['name']} (${p['kind']})'),
                    ],
                    onChanged: (v) => set(() => personId = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record'),
            ),
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
    if (context.mounted) {
      say(
        context,
        'Recorded: $kind ${row['qty']} × ${refs.itemNames[itemId]}.',
      );
    }
    return true;
  } on ArgumentError catch (e) {
    if (context.mounted) say(context, e.message as String);
  } catch (e) {
    if (context.mounted) say(context, 'Could not record: $e');
  }
  return false;
}

/// An item's details: its note from the spreadsheet, and whether the public /kit/ list offers it.
Future<void> showItem(BuildContext context, Rec i) async {
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || lendable == (i['lendable'] == true)) return;
  try {
    await setLendable(i['id'] as int, lendable);
    i['lendable'] = lendable;
  } catch (e) {
    if (context.mounted) say(context, 'Could not save: $e');
  }
}
