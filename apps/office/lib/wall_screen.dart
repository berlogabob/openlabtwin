// Video wall: the playlist and the controls (docs/STAFF-GUIDE.md, "The video wall"). The wall server on the lab node
// reads wall_state and wall_slides every 2 s and reports in wall_status every 10 s.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'logic.dart';
import 'tv_screen.dart' show mmss, tvFolder;

const wallPage = 'http://192.168.1.131:8080/';
const wallModes = {'videowall': 'Videowall: one picture over all screens', 'mosaic': 'Mosaic: one file per screen'};
const wallFits = {'fit': 'Fit (whole picture, black bars)', 'fill': 'Fill (cover, cut the edges)', 'center': 'Center (no scaling)'};

class WallScreen extends StatefulWidget {
  const WallScreen({super.key});

  @override
  State<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends State<WallScreen> {
  List<WallSlide>? slides;
  List<Rec> media = [], events = [];
  Rec? state, status;
  String? error;
  String? previewUrl, previewAt;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([wallSlides(), tvMedia(), wallState(), wallStatus(), tvEvents()]);
      if (!mounted) return;
      setState(() {
        slides = r[0] as List<WallSlide>;
        media = r[1] as List<Rec>;
        state = r[2] as Rec?;
        status = r[3] as Rec?;
        final nextPreviewAt = status?['preview_at'] as String?;
        if (nextPreviewAt != previewAt) {
          previewAt = nextPreviewAt;
          previewUrl = null;
          if (nextPreviewAt != null) {
            wallPreviewUrl().then((url) {
              if (mounted && previewAt == nextPreviewAt) setState(() => previewUrl = url);
            }).catchError((_) {});
          }
        }
        events = r[4] as List<Rec>;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
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
    await _run(() => reorderWallSlides([for (final s in list) s.id!]));
  }

  Future<void> _upload() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media, withData: true);
      final file = result?.files.single;
      if (file == null) return;
      if (file.size > 500 * 1024 * 1024) throw Exception('${file.name} is over 500 MB; copy it to the TV folder on the lab network instead.');
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read ${file.name}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading…')));
      await db.storage.from('wall-upload').uploadBinary(file.name, bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded. It will appear in the file list shortly.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Rec? _file(String name) => media.where((m) => m['name'] == name).firstOrNull;

  String _eventLabel(int? id) {
    final e = events.where((e) => e['id'] == id).firstOrNull;
    if (e == null) return 'event #$id (not upcoming)';
    final start = DateTime.parse(e['starts_at'] as String).toLocal(), end = DateTime.parse(e['ends_at'] as String).toLocal();
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${e['title']} · ${isoDate(start)} ${hm(start)}–${hm(end)}';
  }

  String _render(WallSlide s) => ((status?['slides'] as Map?) ?? const {})['${s.id}'] as String? ?? '';

  Widget _today() {
    final timeline = status?['timeline'];
    if (timeline is! List || timeline.isEmpty) return const SizedBox.shrink();
    String hm(dynamic value) => hhmm(DateTime.parse(value as String).toLocal());
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(dense: true, title: Text('Today')),
          SizedBox(
            height: 160,
            child: ListView(
              children: [
                for (final row in timeline.whereType<Map>())
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text('${hm(row['at'])}–${hm(row['until'])}  ${row['label']}'),
                    subtitle: row['level'] == null ? null : Text('${row['level']}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(WallSlide s) => [
    wallModes[s.mode]!.split(':').first,
    s.mediaNames.isEmpty ? 'all files' : s.mediaNames.join(', '),
    s.fit,
    s.seconds == null ? (s.mode == 'videowall' ? 'whole video' : '30 s') : '${s.seconds} s',
    if (s.cycleSeconds != null) 'next file every ${s.cycleSeconds} s',
    if (s.startsOn != null || s.endsOn != null)
      '${s.startsOn == null ? '…' : isoDate(s.startsOn!)} – ${s.endsOn == null ? '…' : isoDate(s.endsOn!)}',
    if (s.fromTime != null || s.toTime != null) '${s.fromTime ?? '…'}–${s.toTime ?? '…'}',
    if (s.activityId != null) 'during ${_eventLabel(s.activityId)}',
    if (s.takeover) 'takeover',
    if (s.every != null) 'announcement every ${s.every} s',
    if (s.showTitle || s.credits.isNotEmpty || s.logo || s.matte > 0) 'composed',
    if (_render(s).isNotEmpty) _render(s),
  ].join(' · ');

  /// Editor for a playlist entry, or (now: true) a one-off "show this now" without a row.
  Future<WallSlide?> _form(WallSlide s, {bool now = false}) async {
    final title = TextEditingController(text: s.title), credits = TextEditingController(text: s.credits);
    final seconds = TextEditingController(text: s.seconds?.toString() ?? ''),
        cycle = TextEditingController(text: s.cycleSeconds?.toString() ?? '');
    final every = TextEditingController(text: s.every?.toString() ?? ''), matte = TextEditingController(text: '${s.matte}');
    var mode = s.mode, fit = s.fit, showTitle = s.showTitle, logo = s.logo, takeover = s.takeover, preset = s.preset;
    var names = [...s.mediaNames];
    DateTime? from = s.startsOn, to = s.endsOn;
    String? fromTime = s.fromTime, toTime = s.toTime;
    int? activityId = events.any((e) => e['id'] == s.activityId) ? s.activityId : null;
    Future<String?> pickTime(String? t) async {
      final v = await showTimePicker(
        context: context,
        initialTime: t == null
            ? const TimeOfDay(hour: 17, minute: 0)
            : TimeOfDay(hour: int.parse(t.substring(0, 2)), minute: int.parse(t.substring(3))),
      );
      return v == null ? null : '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    }

    Future<DateTime?> pick(DateTime? d) =>
        showDatePicker(context: context, initialDate: d ?? DateTime.now(), firstDate: DateTime(2026), lastDate: DateTime(2030));
    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(now ? 'Show now' : (s.id == null ? 'Add to the wall playlist' : 'Edit wall entry')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: [for (final e in wallModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() {
                    mode = v!;
                    if (mode == 'videowall' && names.length > 1) names = [names.first];
                  }),
                ),
                if (mode == 'videowall')
                  DropdownButtonFormField<String?>(
                    initialValue: names.isNotEmpty && _file(names.first) != null ? names.first : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'File from the TV folder'),
                    items: [
                      for (final m in media)
                        DropdownMenuItem<String?>(
                          value: m['name'] as String,
                          child: Text(
                            '${m['name']}${m['seconds'] == null ? '' : ' (${mmss(m['seconds'] as num)})'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => set(() => names = v == null ? [] : [v]),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [const Expanded(child: Text('Files (none ticked: every file in the folder)')), TextButton.icon(onPressed: _upload, icon: const Icon(Icons.upload), label: const Text('Upload'))]),
                  ),
                  for (final m in media)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m['name'] as String, overflow: TextOverflow.ellipsis),
                      value: names.contains(m['name']),
                      onChanged: (v) => set(() => v == true ? names.add(m['name'] as String) : names.remove(m['name'])),
                    ),
                  TextField(
                    controller: cycle,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Next file every … seconds (empty: no cycling)'),
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: fit,
                  decoration: const InputDecoration(labelText: 'Fit'),
                  items: [for (final e in wallFits.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => fit = v!),
                ),
                if (!now)
                  TextField(
                    controller: seconds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Seconds on the wall',
                      helperText: 'Empty: a video plays to its end; a still 10 s; a mosaic 30 s',
                    ),
                  ),
                if (mode == 'videowall') ...[
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Draw the title on the wall'),
                    value: showTitle,
                    onChanged: (v) => set(() => showTitle = v),
                  ),
                  TextField(
                    controller: credits,
                    decoration: const InputDecoration(labelText: 'Credits (small, bottom right)'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Logo (top right)'),
                    value: logo,
                    onChanged: (v) => set(() => logo = v),
                  ),
                  TextField(
                    controller: matte,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Matte: black frame in px (0 to 400)'),
                  ),
                ],
                if (!now) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show as a preset button'),
                    value: preset,
                    onChanged: (v) => set(() => preset = v),
                  ),
                  DropdownButtonFormField<int?>(
                    initialValue: activityId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Play during a schedule event (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('No: use the dates and times below')),
                      for (final e in events)
                        DropdownMenuItem<int?>(
                          value: e['id'] as int,
                          child: Text(_eventLabel(e['id'] as int), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => set(() => activityId = v),
                  ),
                  if (activityId == null) ...[
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
                          TextButton(onPressed: () => set(() => fromTime = toTime = null), child: const Text('Clear times')),
                      ],
                    ),
                  ],
                  TextField(
                    controller: every,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Announcement: show every … seconds',
                      helperText: 'Same timing as the TV: the same number interrupts both at the same second',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Takeover'),
                    subtitle: const Text('During its dates and times the wall plays only takeover entries'),
                    value: takeover,
                    onChanged: (v) => set(() => takeover = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (s.id != null && !now) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: Text(now ? 'Show now' : 'Save')),
          ],
        ),
      ),
    );
    if (action == 'delete') {
      await _run(() => deleteWallSlide(s.id!));
      return null;
    }
    if (action != 'save') return null;
    final out = WallSlide(
      id: s.id,
      mode: mode,
      title: title.text,
      mediaNames: names,
      seconds: int.tryParse(seconds.text.trim()),
      cycleSeconds: mode == 'mosaic' ? int.tryParse(cycle.text.trim()) : null,
      fit: fit,
      showTitle: mode == 'videowall' && showTitle,
      credits: mode == 'videowall' ? credits.text : '',
      logo: mode == 'videowall' && logo,
      matte: mode == 'videowall' ? int.tryParse(matte.text.trim()) ?? 0 : 0,
      position: s.position,
      active: s.active,
      startsOn: from,
      endsOn: to,
      fromTime: fromTime,
      toTime: toTime,
      takeover: takeover,
      every: int.tryParse(every.text.trim()),
      activityId: activityId,
      preset: preset,
    );
    final problem = out.problem();
    if (problem != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return null;
    }
    return out;
  }

  Future<void> _edit(WallSlide s) async {
    final out = await _form(s);
    if (out != null) await _run(() => saveWallSlide(out));
  }

  Future<void> _showNow() async {
    final out = await _form(WallSlide(), now: true);
    if (out == null) return;
    // 3 s ahead: time for the Pis to fetch the first tiles, so all screens start together
    final at = DateTime.now().toUtc().add(const Duration(seconds: 3)).toIso8601String();
    await _run(() => setWallState({'now': out.toRow(), 'now_at': at, 'now_until': null}));
  }

  Future<void> _showSlideNow(WallSlide slide) async {
    final at = DateTime.now().toUtc().add(const Duration(seconds: 3)).toIso8601String();
    await _run(() => setWallState({'now': slide.toRow(), 'now_at': at, 'now_until': null}));
  }

  Future<void> _emergencyMessage() async {
    final text = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency message'),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Message', hintText: 'Type the message for every screen'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Show on wall')),
        ],
      ),
    );
    text.dispose();
    if (message == null) return;
    if (message.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a message first.')));
      return;
    }
    await _run(() => setWallState({'now': {'mode': 'videowall', 'text': message, 'fit': 'fit'}, 'now_until': null}));
  }

  /// Identify (10 s, big code on each screen) or Test pattern (60 s), on one screen or 'all'. Above everything else.
  Future<void> _overlay(String kind, String code) {
    final until = DateTime.now().toUtc().add(Duration(seconds: kind == 'identify' ? 10 : 60)).toIso8601String();
    return _run(
      () => setWallState({
        'overlay': {'kind': kind, 'code': code, 'until': until},
      }),
    );
  }

  Future<void> _command(String kind, String code) => _run(
    () => setWallState({
      'command': {'kind': kind, 'code': code, 'at': DateTime.now().toUtc().toIso8601String()},
    }),
  );

  Future<void> _rebootAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reboot every wall screen?'),
        content: const Text('The Pis will reboot one at a time, 30 seconds apart.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reboot all')),
        ],
      ),
    );
    if (confirmed == true) await _command('reboot', 'all');
  }

  Future<void> _editSleep() async {
    final sleep = state?['sleep'] as Map?;
    String from = sleep?['from'] as String? ?? '20:00';
    String to = sleep?['to'] as String? ?? '08:00';
    Future<String?> pick(String value) async {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.parse(value.substring(0, 2)), minute: int.parse(value.substring(3))),
      );
      return time == null ? null : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Night sleep'),
          content: Row(children: [
            TextButton(onPressed: () async { final v = await pick(from); if (v != null) set(() => from = v); }, child: Text(from)),
            const Text(' – '),
            TextButton(onPressed: () async { final v = await pick(to); if (v != null) set(() => to = v); }, child: Text(to)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save == true) await _run(() => setWallState({'sleep': {'from': from, 'to': to}}));
  }

  Future<void> _screenMenu(String code) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Screen ${code.toUpperCase()}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'identify'), child: const Text('Identify (10 s)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'test'), child: const Text('Test pattern (60 s)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'restart'), child: const Text('Restart client')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'reboot'), child: const Text('Reboot Pi')),
        ],
      ),
    );
    if (action == 'identify' || action == 'test') await _overlay(action!, code);
    if (action == 'restart' || action == 'reboot') await _command(action!, code);
  }

  Widget _grid() {
    final screens = ((status?['screens'] as Map?) ?? const {}).cast<String, dynamic>();
    if (screens.isEmpty) return const SizedBox.shrink();
    final stale = wallStaleLine(status, DateTime.now()) != null;
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    String lastSeen(Map s) {
      final at = s['seen_at'] ?? status?['seen_at'];
      return at == null ? 'last seen unknown' : 'last seen ${hm(DateTime.parse(at as String).toLocal())}';
    }
    Color colour(Map s) => stale || s['on'] != true
        ? Colors.grey
        : piPower(s['throttled'] as String?) != null || ((s['drift_ms'] as num?)?.abs() ?? 0) > 100
        ? Colors.orange
        : Colors.green;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) {
              final bad = [
                for (final e in screens.entries)
                  if ((e.value as Map)['on'] == true && piPower((e.value as Map)['throttled'] as String?) != null)
                    '${e.key.toUpperCase()}: ${piPower((e.value as Map)['throttled'] as String?)}',
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  bad.isEmpty ? 'Power: all screens on clean power' : 'Power: ${bad.join(' · ')}',
                  style: TextStyle(color: bad.isEmpty ? null : Colors.orange.shade800),
                ),
              );
            },
          ),
          for (final row in wallGrid(screens.keys))
            Row(
              children: [
                for (final c in row)
                  InkWell(
                    onTap: () => _screenMenu(c),
                    child: Tooltip(
                      message: stale
                          ? lastSeen(screens[c] as Map)
                          : '${c.toUpperCase()}: ${(screens[c] as Map)['on'] == true ? 'on' : 'off'}'
                          '${piPower((screens[c] as Map)['throttled'] as String?) == null ? '' : ' · ${piPower((screens[c] as Map)['throttled'] as String?)}'}'
                          ' · drift ${(screens[c] as Map)['drift_ms'] ?? '?'} ms · ${(screens[c] as Map)['temp'] ?? '?'} °C',
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        width: 34,
                        height: 26,
                        alignment: Alignment.center,
                        color: colour(screens[c] as Map),
                        child: Text(c.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = slides;
    final blackout = state?['blackout'] == true, playing = state?['playing'] != false, hasNow = state?['now'] != null;
    final sleep = state?['sleep'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video wall'),
        actions: [IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: list == null ? null : () => _edit(WallSlide(position: list.length)),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: error != null
          ? Center(child: Text(error!))
          : list == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Builder(
                  builder: (context) {
                    final now = DateTime.now();
                    final stale = wallStaleLine(status, now);
                    final st = wallStatusLine(status, now);
                    return ListTile(
                      dense: true,
                      leading: stale == null ? Icon(st.ok ? Icons.check_circle : Icons.warning, color: st.ok ? Colors.green : Colors.red) : null,
                      title: Text(stale ?? st.text, style: TextStyle(color: stale != null ? Colors.grey : (st.ok ? null : Colors.red))),
                    );
                  },
                ),
                if (previewUrl != null) Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.network(previewUrl!, height: 180, fit: BoxFit.contain),
                ),
                _today(),
                _grid(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        style: blackout ? FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white) : null,
                        onPressed: () => _run(() => setWallState({'blackout': !blackout})),
                        child: Text(blackout ? 'Blackout on: turn off' : 'Blackout'),
                      ),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.nights_stay_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text('Night sleep ${sleep?['from'] ?? '20:00'}–${sleep?['to'] ?? '08:00'}'),
                        TextButton(onPressed: _editSleep, child: const Text('[edit]')),
                      ]),
                      FilledButton.tonal(
                        onPressed: () => _run(() => setWallState({'playing': !playing})),
                        child: Text(playing ? 'Stop' : 'Play'),
                      ),
                      FilledButton.tonal(onPressed: _showNow, child: const Text('Show now…')),
                      OutlinedButton(onPressed: _emergencyMessage, child: const Text('Emergency message…')),
                      OutlinedButton(onPressed: () => _overlay('identify', 'all'), child: const Text('Identify all')),
                      OutlinedButton(onPressed: () => _overlay('test', 'all'), child: const Text('Test pattern')),
                      OutlinedButton(onPressed: _rebootAll, child: const Text('Reboot all (30 s apart)')),
                      if (hasNow)
                        FilledButton.tonal(
                          onPressed: () => _run(() => setWallState({'now': null, 'now_at': null, 'now_until': null})),
                          child: const Text('Back to schedule'),
                        ),
                    ],
                  ),
                ),
                if (list.any((s) => s.preset))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in list.where((s) => s.preset))
                            FilledButton.tonal(
                              onPressed: () => _showSlideNow(s),
                              child: Text(s.title.isNotEmpty ? s.title : (s.mediaNames.isEmpty ? 'All files' : s.mediaNames.first)),
                            ),
                        ],
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SelectionArea(
                    child: Text(
                      'The wall plays these entries in this order, then starts again, with the TV\'s rules for dates, '
                      'times, takeover and announcements. Drag to reorder, tap to edit, the switch hides an entry. '
                      'Tap a screen square for Identify or Test pattern on that screen.\n'
                      'Files: $tvFolder (the TV\'s folder)   ·   Setup page: $wallPage (lab network)',
                    ),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('No entries yet: the wall shows its test images.'))
                      : ReorderableListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          onReorderItem: _reorder,
                          children: [
                            for (final s in list)
                              ListTile(
                                key: ValueKey(s.id),
                                leading: Switch(value: s.active, onChanged: (v) => _run(() => saveWallSlide(s..active = v))),
                                trailing: IconButton(
                                  tooltip: 'Show now',
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: () => _showSlideNow(s),
                                ),
                                title: Text(s.title.isNotEmpty ? s.title : (s.mediaNames.isEmpty ? 'All files' : s.mediaNames.first)),
                                subtitle: Text(_subtitle(s), style: TextStyle(color: _render(s).startsWith('failed') ? Colors.red : null)),
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
