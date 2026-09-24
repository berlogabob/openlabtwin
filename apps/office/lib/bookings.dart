// Bookings list and the booking form (requester, rooms, repeat, equipment, clash warnings, approval).
import 'package:flutter/material.dart';

import 'data.dart';
import 'hours.dart';
import 'ideas_screen.dart';
import 'inventory.dart';
import 'logic.dart';
import 'tv_screen.dart';

const statusColors = {
  'requested': Colors.orange,
  'approved': Colors.green,
  'rejected': Colors.grey,
  'cancelled': Colors.grey,
  'done': Colors.blueGrey,
};

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  late Future<(Refs, List<Activity>)> data = _load();

  Future<(Refs, List<Activity>)> _load() async => (await loadRefs(), await upcoming());

  Future<void> _open(Refs refs, Activity? a) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1, 10);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BookingForm(
        refs: refs,
        activity: a ?? Activity(start: start, end: start.add(const Duration(hours: 2)), ownerStaffId: refs.me),
      ),
    ));
    setState(() => data = _load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: data,
        builder: (context, snap) {
          final loaded = snap.data;
          return Scaffold(
            appBar: AppBar(title: const Text('Lab bookings'), actions: [
              IconButton(
                tooltip: 'TV',
                icon: const Icon(Icons.tv),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TvScreen())),
              ),
              IconButton(
                tooltip: 'Ideas',
                icon: const Icon(Icons.lightbulb_outline),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const IdeasScreen())),
              ),
              if (loaded != null)
                IconButton(
                  tooltip: 'Consultation hours',
                  icon: const Icon(Icons.schedule),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HoursPage(refs: loaded.$1))),
                ),
              if (loaded != null)
                IconButton(
                  tooltip: 'Inventory',
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InventoryPage(refs: loaded.$1))),
                ),
              IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => setState(() => data = _load())),
              IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => db.auth.signOut()),
            ]),
            floatingActionButton: loaded == null
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _open(loaded.$1, null), icon: const Icon(Icons.add), label: const Text('New booking')),
            body: snap.hasError
                ? Center(child: Text('Could not load: ${snap.error}'))
                : loaded == null
                    ? const Center(child: CircularProgressIndicator())
                    : loaded.$2.isEmpty
                        ? const Center(child: Text('No upcoming bookings.'))
                        : ListView(children: [
                            for (final a in loaded.$2)
                              ListTile(
                                title: Text(a.title),
                                subtitle: Text([
                                  a.when(),
                                  _rooms(loaded.$1, a),
                                  a.requesterDisplay,
                                ].where((s) => s.isNotEmpty).join(' · ')),
                                trailing: Chip(label: Text(a.status), backgroundColor: statusColors[a.status]?.withAlpha(60)),
                                onTap: () => _open(loaded.$1, a),
                              ),
                          ]),
          );
        },
      );
}

String _rooms(Refs refs, Activity a) => [
      for (final r in refs.rooms)
        if (a.placeIds.contains(r['id'])) r['name'] as String,
      if (a.locationText.isNotEmpty) a.locationText,
    ].join(', ');

class BookingForm extends StatefulWidget {
  const BookingForm({super.key, required this.refs, required this.activity});
  final Refs refs;
  final Activity activity;

  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  late final a = widget.activity;
  late final refs = widget.refs;
  late final title = TextEditingController(text: a.title);
  late final location = TextEditingController(text: a.locationText);
  late final display = TextEditingController(text: a.requesterDisplay);
  late final attendees = TextEditingController(text: a.attendees?.toString() ?? '');
  late final purpose = TextEditingController(text: a.purpose);
  late final note = TextEditingController(text: a.publicNote);
  late final skip = TextEditingController(text: a.exdates.join(', '));
  List<Rec> kit = [];
  List<Rec> past = []; // the requester's lab history
  List<String>? warnings;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (a.id != null) _loadKit();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (a.requesterId == null) return setState(() => past = []);
    final rows = await history(a.requesterId!);
    setState(() => past = [for (final r in rows) if (r['id'] != a.id) r]);
  }

  Future<void> _loadKit() async {
    final rows = await equipment(a.id!);
    setState(() => kit = rows);
  }

  void _collect() {
    a
      ..title = title.text
      ..locationText = location.text
      ..requesterDisplay = display.text
      ..attendees = int.tryParse(attendees.text.trim())
      ..purpose = purpose.text
      ..publicNote = note.text
      ..exdates = [for (final s in skip.text.split(',')) if (s.trim().isNotEmpty) s.trim()];
  }

  Future<void> _save([String? status]) async {
    _collect();
    if (a.title.trim().isEmpty) return _say('Give the booking a title.');
    if (!a.end.isAfter(a.start)) return _say('The end time must be after the start.');
    if (a.placeIds.isEmpty && a.locationText.trim().isEmpty) return _say('Pick a room or type a location.');
    setState(() => busy = true);
    try {
      if (status != null) a.status = status;
      a.id = await saveActivity(a);
      final w = await clashWarnings(a, refs);
      setState(() => warnings = w);
      _say(a.status == 'approved'
          ? 'Saved and approved. The public site shows it within about 15 minutes.'
          : 'Saved (${a.status}).');
    } catch (e) {
      _say('Could not save: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: a.start, firstDate: DateTime(2025), lastDate: DateTime(2030));
    if (d == null) return;
    setState(() {
      a.start = DateTime(d.year, d.month, d.day, a.start.hour, a.start.minute);
      a.end = DateTime(d.year, d.month, d.day, a.end.hour, a.end.minute);
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(isStart ? a.start : a.end));
    if (t == null) return;
    setState(() {
      final base = a.start;
      final v = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (isStart) {
        final length = a.end.difference(a.start);
        a
          ..start = v
          ..end = v.add(length);
      } else {
        a.end = v;
      }
    });
  }

  Future<void> _pickUntil() async {
    final d = await showDatePicker(
        context: context, initialDate: a.repeatUntil ?? a.start.add(const Duration(days: 91)), firstDate: a.start, lastDate: DateTime(2030));
    if (d != null) setState(() => a.repeatUntil = d);
  }

  Future<void> _newPerson() async {
    final name = TextEditingController(), email = TextEditingController();
    var kind = 'professor';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('New person'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email (private)')),
            DropdownButton<String>(
              value: kind,
              isExpanded: true,
              items: [for (final k in const ['professor', 'student', 'staff', 'external']) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => set(() => kind = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final p = await addPerson(name.text, kind, email.text);
    setState(() {
      refs.people.add(p);
      _setRequester(p);
    });
  }

  void _setRequester(Rec p) {
    a.requesterId = p['id'] as int;
    _loadHistory();
    if (display.text.trim().isEmpty) display.text = p['kind'] == 'professor' ? 'Prof. ${p['name']}' : p['name'] as String;
  }

  Future<void> _addKit() async {
    Rec? item;
    final qty = TextEditingController(text: '1');
    final newName = TextEditingController();
    var newKind = 'portable';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Add equipment'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<Rec?>(
              value: item,
              isExpanded: true,
              hint: const Text('Existing item, or type a new one below'),
              items: [for (final i in refs.items) DropdownMenuItem(value: i, child: Text('${i['name']} (${i['kind']})'))],
              onChanged: (v) => set(() => item = v),
            ),
            TextField(controller: newName, decoration: const InputDecoration(labelText: 'New item name')),
            DropdownButton<String>(
              value: newKind,
              isExpanded: true,
              items: [for (final k in const ['portable', 'consumable', 'stationary']) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => set(() => newKind = v!),
            ),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (item == null && newName.text.trim().isNotEmpty) {
      item = await addItem(newName.text, newKind);
      refs.items.add(item!);
    }
    if (item == null) return;
    await setEquipment(a.id!, item!['id'] as int, num.tryParse(qty.text) ?? 1, false);
    await _loadKit();
  }

  /// Issue or return the whole equipment list in one go, as movements linked to this booking.
  Future<void> _kit(String kind) async {
    int? placeId = [for (final p in refs.places) if (p['tier'] == 'fast') p['id'] as int].firstOrNull;
    int? personId = a.requesterId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(kind == 'issue' ? 'Issue kit' : 'Return kit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<int?>(
              value: placeId,
              isExpanded: true,
              hint: Text(kind == 'issue' ? 'From' : 'Back to'),
              items: [for (final p in refs.places) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
              onChanged: (v) => set(() => placeId = v),
            ),
            DropdownButton<int?>(
              value: personId,
              isExpanded: true,
              hint: Text(kind == 'issue' ? 'Given to' : 'Returned by'),
              items: [for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))],
              onChanged: (v) => set(() => personId = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(kind == 'issue' ? 'Issue' : 'Return')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final rows = [
        for (final k in kit)
          movementRow(
              kind: kind, itemId: k['item_id'] as int, qty: k['qty'] as num, from: placeId, to: placeId, personId: personId, activityId: a.id, byStaff: refs.me),
      ];
      if (kind == 'issue') {
        final short = shortages(kit, placeId!, await stock(), refs.itemNames);
        if (short.isNotEmpty && mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Not enough in stock there'),
              content: Text('${short.join('\n')}\n\nIssue anyway? Stock will go negative until you record a receive or move.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Issue anyway')),
              ],
            ),
          );
          if (go != true) return;
        }
      }
      await addMovements(rows);
      _say('${kind == 'issue' ? 'Issued' : 'Returned'} ${rows.length} line(s).');
    } on ArgumentError catch (e) {
      _say(e.message as String);
    } catch (e) {
      _say('Could not record: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = a.start;
    return Scaffold(
      appBar: AppBar(title: Text(a.id == null ? 'New booking' : 'Booking'), actions: [
        if (busy) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator())),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, children: [
          Chip(label: Text('Status: ${a.status}'), backgroundColor: statusColors[a.status]?.withAlpha(60)),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'booking', label: Text('Booking')), ButtonSegment(value: 'event', label: Text('Event'))],
            selected: {a.layer},
            onSelectionChanged: (v) => setState(() => a.layer = v.first),
          ),
        ]),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title (public)')),
        DropdownButtonFormField<String>(
          initialValue: a.kind,
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => a.kind = v!,
        ),
        const SizedBox(height: 12),
        Text('Rooms', style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 8, children: [
          for (final r in refs.rooms)
            FilterChip(
              label: Text(r['name'] as String),
              selected: a.placeIds.contains(r['id']),
              onSelected: (on) => setState(() => on ? a.placeIds.add(r['id'] as int) : a.placeIds.remove(r['id'])),
            ),
        ]),
        TextField(controller: location, decoration: const InputDecoration(labelText: 'Or off-site location (events)')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(isoDate(s))),
          OutlinedButton(onPressed: () => _pickTime(true), child: Text('from ${hhmm(a.start)}')),
          OutlinedButton(onPressed: () => _pickTime(false), child: Text('to ${hhmm(a.end)}')),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeats weekly'),
          value: a.repeatUntil != null,
          onChanged: (on) => setState(() => a.repeatUntil = on ? s.add(const Duration(days: 91)) : null),
        ),
        if (a.repeatUntil != null) ...[
          OutlinedButton(onPressed: _pickUntil, child: Text('until ${isoDate(a.repeatUntil!)}')),
          TextField(controller: skip, decoration: const InputDecoration(labelText: 'Skip dates (YYYY-MM-DD, comma-separated)')),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: a.requesterId,
              decoration: const InputDecoration(labelText: 'Requested by'),
              items: [
                for (final p in refs.people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (${p['kind']})')),
              ],
              onChanged: (v) => setState(() => _setRequester(refs.people.firstWhere((p) => p['id'] == v))),
            ),
          ),
          IconButton(tooltip: 'New person', icon: const Icon(Icons.person_add), onPressed: _newPerson),
        ]),
        TextField(controller: display, decoration: const InputDecoration(labelText: 'Shown on the site as (e.g. Prof. Cláudia)')),
        if (a.contactLink.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectionArea(child: Text('Their link: ${a.contactLink}'))),
        if (past.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Their history (${past.length})'),
            children: [
              for (final h in past)
                ListTile(
                  dense: true,
                  title: Text('${(h['starts_at'] as String).substring(0, 10)} · ${h['kind']} · ${h['status']}'),
                  subtitle: Text([h['title'], h['purpose'] ?? ''].where((x) => '$x'.isNotEmpty).join(' — ')),
                ),
            ],
          ),
        DropdownButtonFormField<int?>(
          initialValue: a.organizationId,
          decoration: const InputDecoration(labelText: 'Club / course / project (optional)'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('—')),
            for (final o in refs.orgs) DropdownMenuItem(value: o['id'] as int, child: Text(o['name'] as String)),
          ],
          onChanged: (v) => a.organizationId = v,
        ),
        TextField(controller: attendees, decoration: const InputDecoration(labelText: 'People attending'), keyboardType: TextInputType.number),
        TextField(controller: purpose, decoration: const InputDecoration(labelText: 'Purpose and notes (private)'), maxLines: 3),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Public note (shown on the site)')),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: busy ? null : () => _save(), child: const Text('Save')),
          if (a.status != 'approved')
            FilledButton.tonal(onPressed: busy ? null : () => _save('approved'), child: const Text('Approve')),
          if (a.status == 'requested') OutlinedButton(onPressed: busy ? null : () => _save('rejected'), child: const Text('Reject')),
          if (a.status == 'approved') OutlinedButton(onPressed: busy ? null : () => _save('cancelled'), child: const Text('Cancel booking')),
          if (a.status == 'approved') OutlinedButton(onPressed: busy ? null : () => _save('done'), child: const Text('Mark done')),
        ]),
        if (warnings != null) ...[
          const SizedBox(height: 16),
          Text(warnings!.isEmpty ? 'No clashes.' : 'Clashes (${warnings!.length}):', style: Theme.of(context).textTheme.titleSmall),
          for (final w in warnings!.take(20)) Text('• $w', style: const TextStyle(color: Colors.deepOrange)),
        ],
        const Divider(height: 32),
        Text('Equipment to prepare', style: Theme.of(context).textTheme.titleMedium),
        if (a.id == null) const Text('Save the booking first, then add equipment.'),
        for (final k in kit)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: k['prepared'] as bool,
            title: Text('${k['qty']} × ${(k['items'] as Rec)['name']}'),
            secondary: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await removeEquipment(a.id!, k['item_id'] as int);
                await _loadKit();
              },
            ),
            onChanged: (v) async {
              await setEquipment(a.id!, k['item_id'] as int, k['qty'] as num, v ?? false);
              await _loadKit();
            },
          ),
        if (a.id != null)
          Wrap(spacing: 8, children: [
            TextButton.icon(onPressed: _addKit, icon: const Icon(Icons.add), label: const Text('Add equipment')),
            if (kit.isNotEmpty) TextButton.icon(onPressed: () => _kit('issue'), icon: const Icon(Icons.outbox), label: const Text('Issue kit')),
            if (kit.isNotEmpty) TextButton.icon(onPressed: () => _kit('return'), icon: const Icon(Icons.move_to_inbox), label: const Text('Return kit')),
          ]),
      ]),
    );
  }
}
