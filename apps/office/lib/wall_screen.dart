// Video wall: the playlist and the controls (docs/STAFF-GUIDE.md, "The video wall"). The wall server on the lab node
// reads wall_state and wall_slides every 2 s and reports in wall_status every 10 s.
import 'dart:async';

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

  Rec? _file(String name) => media.where((m) => m['name'] == name).firstOrNull;

  String _eventLabel(int? id) {
    final e = events.where((e) => e['id'] == id).firstOrNull;
    if (e == null) return 'event #$id (not upcoming)';
    final start = DateTime.parse(e['starts_at'] as String).toLocal(), end = DateTime.parse(e['ends_at'] as String).toLocal();
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${e['title']} · ${isoDate(start)} ${hm(start)}–${hm(end)}';
  }

  String _render(WallSlide s) => ((status?['slides'] as Map?) ?? const {})['${s.id}'] as String? ?? '';

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
    var mode = s.mode, fit = s.fit, showTitle = s.showTitle, logo = s.logo, takeover = s.takeover;
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
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('Files (none ticked: every file in the folder)')),
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

  /// Identify (10 s, big code on each screen) or Test pattern (60 s), on one screen or 'all'. Above everything else.
  Future<void> _overlay(String kind, String code) {
    final until = DateTime.now().toUtc().add(Duration(seconds: kind == 'identify' ? 10 : 60)).toIso8601String();
    return _run(
      () => setWallState({
        'overlay': {'kind': kind, 'code': code, 'until': until},
      }),
    );
  }

  Future<void> _screenMenu(String code) async {
    final kind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Screen ${code.toUpperCase()}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'identify'), child: const Text('Identify (10 s)')),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'test'), child: const Text('Test pattern (60 s)')),
        ],
      ),
    );
    if (kind != null) await _overlay(kind, code);
  }

  Widget _grid() {
    final screens = ((status?['screens'] as Map?) ?? const {}).cast<String, dynamic>();
    if (screens.isEmpty) return const SizedBox.shrink();
    Color colour(Map s) => s['on'] != true
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
                      message:
                          '${c.toUpperCase()}: ${(screens[c] as Map)['on'] == true ? 'on' : 'off'}'
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
                    final st = wallStatusLine(status, DateTime.now());
                    return ListTile(
                      dense: true,
                      leading: Icon(st.ok ? Icons.check_circle : Icons.warning, color: st.ok ? Colors.green : Colors.red),
                      title: Text(st.text, style: TextStyle(color: st.ok ? null : Colors.red)),
                    );
                  },
                ),
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
                      FilledButton.tonal(
                        onPressed: () => _run(() => setWallState({'playing': !playing})),
                        child: Text(playing ? 'Stop' : 'Play'),
                      ),
                      FilledButton.tonal(onPressed: _showNow, child: const Text('Show now…')),
                      OutlinedButton(onPressed: () => _overlay('identify', 'all'), child: const Text('Identify all')),
                      OutlinedButton(onPressed: () => _overlay('test', 'all'), child: const Text('Test pattern')),
                      if (hasNow)
                        FilledButton.tonal(
                          onPressed: () => _run(() => setWallState({'now': null, 'now_at': null, 'now_until': null})),
                          child: const Text('Back to schedule'),
                        ),
                    ],
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
