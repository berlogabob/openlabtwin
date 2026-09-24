// Consultation hours: the weekly slots students can book through the "Book me" QR form.
import 'package:flutter/material.dart';

import 'data.dart';

const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class HoursPage extends StatefulWidget {
  const HoursPage({super.key, required this.refs});
  final Refs refs;

  @override
  State<HoursPage> createState() => _HoursPageState();
}

class _HoursPageState extends State<HoursPage> {
  late final refs = widget.refs;
  late Future<List<Rec>> rows = consultationHours();

  String _hm(String t) => t.substring(0, 5);
  String _t(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    var weekday = 2; // Tuesday
    var from = const TimeOfDay(hour: 14, minute: 0), to = const TimeOfDay(hour: 17, minute: 0);
    var slot = 30;
    int? placeId = refs.rooms.isEmpty ? null : refs.rooms.first['id'] as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Add consultation hours'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<int>(
              value: weekday,
              isExpanded: true,
              items: [for (var i = 1; i <= 7; i++) DropdownMenuItem(value: i, child: Text(weekdays[i - 1]))],
              onChanged: (v) => set(() => weekday = v!),
            ),
            Row(children: [
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: from);
                  if (t != null) set(() => from = t);
                },
                child: Text('from ${_t(from)}'),
              ),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: to);
                  if (t != null) set(() => to = t);
                },
                child: Text('to ${_t(to)}'),
              ),
            ]),
            DropdownButton<int>(
              value: slot,
              isExpanded: true,
              items: [for (final m in const [15, 20, 30, 45, 60]) DropdownMenuItem(value: m, child: Text('$m-minute slots'))],
              onChanged: (v) => set(() => slot = v!),
            ),
            DropdownButton<int?>(
              value: placeId,
              isExpanded: true,
              items: [for (final r in refs.rooms) DropdownMenuItem(value: r['id'] as int, child: Text(r['name'] as String))],
              onChanged: (v) => set(() => placeId = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || placeId == null || refs.me == null) return;
    try {
      await addConsultationHours(refs.me!, placeId!, weekday, _t(from), _t(to), slot);
      setState(() => rows = consultationHours());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Consultation hours')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add hours')),
        body: FutureBuilder(
          future: rows,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
            final list = snap.data;
            if (list == null) return const Center(child: CircularProgressIndicator());
            return ListView(children: [
              const ListTile(
                title: Text('Students book these slots with the "Book me" QR code; lessons and bookings in the room are left out.'),
              ),
              if (list.isEmpty) const ListTile(title: Text('No hours yet: students see no free times.')),
              for (final h in list)
                ListTile(
                  title: Text('${weekdays[(h['weekday'] as int) - 1]} ${_hm(h['from_time'] as String)}–${_hm(h['to_time'] as String)}'),
                  subtitle: Text('${h['slot_minutes']}-minute slots · ${(h['places'] as Rec)['name']} · ${(h['people'] as Rec)['name']}'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await removeConsultationHours(h['id'] as int);
                      setState(() => rows = consultationHours());
                    },
                  ),
                ),
            ]);
          },
        ),
      );
}
