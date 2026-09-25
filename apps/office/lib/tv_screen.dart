// TV showcase: the slides the lab TV plays beside the schedule (docs/STAFF-GUIDE.md, "The TV").
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';

const tvAddress = 'http://192.168.1.131/tv/';
const tvFolder = 'smb://192.168.1.131/tv';
const slideKinds = {
  'media': 'Video or photo',
  'bio': 'Bio',
  'qr': 'QR code',
  'text': 'Text',
  'events': 'Upcoming events (automatic)',
  'ideas': '3 random student ideas (automatic)',
};

/// 389.6 -> '6:30'
String mmss(num s) => '${s ~/ 60}:${(s.round() % 60).toString().padLeft(2, '0')}';

String mediaLabel(Rec m) => '${m['name']}${m['playable'] == true ? '' : " (won't play on the TV)"}';

class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  List<TvSlide>? slides;
  List<Rec> media = [];
  Rec? status;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([tvSlides(), tvMedia(), tvStatus()]);
      setState(() {
        slides = r[0] as List<TvSlide>;
        media = r[1] as List<Rec>;
        status = r[2] as Rec?;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Future<void> _reorder(int from, int to) async {
    final list = [...slides!];
    list.insert(to, list.removeAt(from));
    setState(() => slides = list);
    await _run(() => reorderTvSlides([for (final s in list) s.id!]));
  }

  String _subtitle(TvSlide s) => [
    slideKinds[s.kind]!,
    if (s.mediaName != null) s.mediaName!,
    s.seconds == null ? 'whole video' : '${s.seconds} s',
    if (s.startsOn != null || s.endsOn != null)
      '${s.startsOn == null ? '…' : isoDate(s.startsOn!)} – ${s.endsOn == null ? '…' : isoDate(s.endsOn!)}',
    if (s.fromTime != null || s.toTime != null) '${s.fromTime ?? '…'}–${s.toTime ?? '…'}',
    if (s.fullscreen) 'full screen',
    if (s.takeover) 'takeover',
    if (!s.showsOn(DateTime.now())) 'not showing today',
  ].join(' · ');

  Rec? _file(String? name) => media.where((m) => m['name'] == name).firstOrNull;
  bool _video(String kind, String? name) => kind == 'media' && _file(name)?['kind'] == 'video';
  String _length(String? name) =>
      _file(name)?['seconds'] == null ? 'full length' : mmss(_file(name)!['seconds'] as num);

  Future<void> _edit(TvSlide s) async {
    final title = TextEditingController(text: s.title), body = TextEditingController(text: s.body);
    final url = TextEditingController(text: s.url), seconds = TextEditingController(text: '${s.seconds ?? 10}');
    var whole = s.seconds == null;
    var kind = s.kind;
    String? mediaName = s.mediaName;
    DateTime? from = s.startsOn, to = s.endsOn;
    String? fromTime = s.fromTime, toTime = s.toTime;
    var fullscreen = s.fullscreen, takeover = s.takeover;
    Future<String?> pickTime(String? t) async {
      final v = await showTimePicker(
        context: context,
        initialTime: t == null
            ? const TimeOfDay(hour: 17, minute: 0)
            : TimeOfDay(hour: int.parse(t.substring(0, 2)), minute: int.parse(t.substring(3))),
      );
      return v == null ? null : '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }

    Future<DateTime?> pick(DateTime? d) => showDatePicker(
      context: context,
      initialDate: d ?? DateTime.now(),
      firstDate: DateTime(2026),
      lastDate: DateTime(2030),
    );
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(s.id == null ? 'Add slide' : 'Edit slide'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: [for (final e in slideKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => kind = v!),
                ),
                if (kind == 'events' || kind == 'ideas')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      kind == 'events' ? 'Plays each approved event of the next 14 days here, one page each.' : "Plays 3 random approved ideas here, in the AI's version, with no names. A new pick every loop.",
                    ),
                  )
                else
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: kind == 'bio'
                          ? 'Name'
                          : kind == 'media'
                          ? 'Caption (optional)'
                          : 'Title',
                    ),
                  ),
                if (kind == 'bio' || kind == 'text')
                  TextField(
                    controller: body,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: kind == 'bio' ? 'Role and short bio' : 'Text'),
                  ),
                if (kind == 'media' || kind == 'bio')
                  DropdownButtonFormField<String?>(
                    key: ValueKey(kind),
                    initialValue: media.any((m) => m['name'] == mediaName) ? mediaName : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: kind == 'bio' ? 'Photo (optional)' : 'File from the TV folder',
                    ),
                    items: [
                      if (kind == 'bio') const DropdownMenuItem<String?>(value: null, child: Text('No photo')),
                      for (final m in media)
                        if (kind == 'media' || m['kind'] == 'photo')
                          DropdownMenuItem<String?>(
                            value: m['name'] as String,
                            child: Text(mediaLabel(m), overflow: TextOverflow.ellipsis),
                          ),
                    ],
                    onChanged: (v) => set(() => mediaName = v),
                  ),
                if (kind == 'qr')
                  TextField(
                    controller: url,
                    decoration: const InputDecoration(labelText: 'Link (https://…)'),
                  ),
                if (_video(kind, mediaName))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Play the whole video (${_length(mediaName)})'),
                    subtitle: whole ? null : const Text('Off: cut it after the seconds below'),
                    value: whole,
                    onChanged: (v) => set(() => whole = v),
                  ),
                if (!_video(kind, mediaName) || !whole)
                  TextField(
                    controller: seconds,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: kind == 'events' || kind == 'ideas' ? 'Seconds per page' : 'Seconds on screen',
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final d = await pick(from);
                        if (d != null) set(() => from = d);
                      },
                      child: Text(from == null ? 'From: now' : 'From ${isoDate(from!)}'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final d = await pick(to);
                        if (d != null) set(() => to = d);
                      },
                      child: Text(to == null ? 'Until: no end' : 'Until ${isoDate(to!)}'),
                    ),
                    if (from != null || to != null)
                      TextButton(onPressed: () => set(() => from = to = null), child: const Text('Clear dates')),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(fromTime);
                        if (t != null) set(() => fromTime = t);
                      },
                      child: Text(fromTime == null ? 'Time from: any' : 'From $fromTime'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final t = await pickTime(toTime);
                        if (t != null) set(() => toTime = t);
                      },
                      child: Text(toTime == null ? 'Time until: any' : 'Until $toTime'),
                    ),
                    if (fromTime != null || toTime != null)
                      TextButton(
                        onPressed: () => set(() => fromTime = toTime = null),
                        child: const Text('Clear times'),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Full screen'),
                  subtitle: const Text('The page fills the TV; the schedule hides while it plays'),
                  value: fullscreen,
                  onChanged: (v) => set(() => fullscreen = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Takeover'),
                  subtitle: const Text('During its dates and times the TV plays only takeover pages, in a loop'),
                  value: takeover,
                  onChanged: (v) => set(() => takeover = v),
                ),
              ],
            ),
          ),
          actions: [
            if (s.id != null)
              TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (action == 'delete') return _run(() => deleteTvSlide(s.id!));
    if (action != 'save') return;
    final slide = TvSlide(
      id: s.id,
      kind: kind,
      title: kind == 'events' || kind == 'ideas' ? slideKinds[kind]! : title.text,
      body: kind == 'bio' || kind == 'text' ? body.text : '',
      mediaName: kind == 'media' || kind == 'bio' ? mediaName : null,
      url: kind == 'qr' ? url.text.trim() : '',
      seconds: _video(kind, mediaName) && whole ? null : int.tryParse(seconds.text.trim()) ?? 0,
      position: s.position,
      startsOn: from,
      endsOn: to,
      active: s.active,
      fromTime: fromTime,
      toTime: toTime,
      fullscreen: fullscreen,
      takeover: takeover,
    );
    final problem = slide.problem();
    if (problem != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await _run(() => saveTvSlide(slide));
  }

  @override
  Widget build(BuildContext context) {
    final list = slides;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV'),
        actions: [IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: list == null ? null : () => _edit(TvSlide(position: list.length)),
        icon: const Icon(Icons.add),
        label: const Text('Add page'),
      ),
      body: error != null
          ? Center(child: Text(error!))
          : list == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Builder(
                  builder: (context) {
                    final st = tvStatusLine(status, DateTime.now());
                    return ListTile(
                      dense: true,
                      leading: Icon(st.ok ? Icons.check_circle : Icons.warning, color: st.ok ? Colors.green : Colors.red),
                      title: Text(st.text, style: TextStyle(color: st.ok ? null : Colors.red)),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SelectionArea(
                    child: Text(
                      'The TV plays these pages in this order, then starts again. '
                      'Drag to reorder, tap to edit, the switch hides a page.\n'
                      'TV: $tvAddress?room=…&room=…   ·   Files: $tvFolder (lab network)',
                    ),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('No pages yet.'))
                      : ReorderableListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          onReorderItem: _reorder,
                          children: [
                            for (final s in list)
                              ListTile(
                                key: ValueKey(s.id),
                                leading: Switch(
                                  value: s.active,
                                  onChanged: (v) => _run(() => saveTvSlide(s..active = v)),
                                ),
                                title: Text(s.title.isNotEmpty ? s.title : s.mediaName ?? slideKinds[s.kind]!),
                                subtitle: Text(_subtitle(s)),
                                onTap: () => _edit(s),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
