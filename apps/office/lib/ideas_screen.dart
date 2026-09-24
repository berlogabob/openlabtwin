// Idea hub, staff side: the idea bank (new / approved / archived), the AI's version, matches, workshop flag.
import 'package:flutter/material.dart';

import 'data.dart';

class IdeasScreen extends StatefulWidget {
  const IdeasScreen({super.key});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  String status = 'new', filter = '';
  late Future<List<Rec>> rows = ideas(status);

  void _reload() => setState(() => rows = ideas(status));

  bool _hit(Rec i) {
    final q = filter.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [i['ai_title'], i['body'], ...(i['ai_keywords'] as List? ?? const [])].any((x) => '${x ?? ''}'.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ideas'), actions: [IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload)]),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'new', label: Text('New')),
                  ButtonSegment(value: 'approved', label: Text('Approved')),
                  ButtonSegment(value: 'archived', label: Text('Archived')),
                ],
                selected: {status},
                onSelectionChanged: (v) => setState(() {
                  status = v.first;
                  rows = ideas(status);
                }),
              ),
              SizedBox(
                width: 260,
                child: TextField(decoration: const InputDecoration(labelText: 'Filter by keyword'), onChanged: (v) => setState(() => filter = v)),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder(
              future: rows,
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
                final list = snap.data?.where(_hit).toList();
                if (list == null) return const Center(child: CircularProgressIndicator());
                if (list.isEmpty) return const Center(child: Text('No ideas here.'));
                return ListView(children: [
                  for (final i in list)
                    ListTile(
                      leading: Icon(i['workshop'] == true ? Icons.school : Icons.lightbulb_outline),
                      title: Text((i['ai_title'] as String?) ?? '(the AI has not read it yet)'),
                      subtitle: Text('${(i['people'] as Rec)['name']} · ${(i['created_at'] as String).substring(0, 10)} · '
                          '${((i['ai_keywords'] as List?) ?? const []).join(', ')}'),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IdeaPage(id: i['id'] as int)));
                        _reload();
                      },
                    ),
                ]);
              },
            ),
          ),
        ]),
      );
}

class IdeaPage extends StatefulWidget {
  const IdeaPage({super.key, required this.id});
  final int id;

  @override
  State<IdeaPage> createState() => _IdeaPageState();
}

class _IdeaPageState extends State<IdeaPage> {
  Rec? idea;
  List<Rec> matches = [], past = [];
  final title = TextEditingController(), summary = TextEditingController(), keywords = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = await idea1(widget.id);
    final m = await ideaMatches(widget.id);
    final p = await personIdeas(i['person_id'] as int);
    setState(() {
      idea = i;
      matches = m;
      past = [for (final x in p) if (x['id'] != widget.id) x];
      title.text = (i['ai_title'] as String?) ?? '';
      summary.text = (i['ai_summary'] as String?) ?? '';
      keywords.text = ((i['ai_keywords'] as List?) ?? const []).join(', ');
    });
  }

  Future<void> _set(Rec change, String said) async {
    try {
      await updateIdea(widget.id, change);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = idea;
    if (i == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final person = i['people'] as Rec;
    return Scaffold(
      appBar: AppBar(title: Text((i['ai_title'] as String?) ?? 'Idea')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${person['name']} · ${person['email'] ?? ''}${person['student_number'] == null ? '' : ' · ${person['student_number']}'}'),
        Text('Status: ${i['status']}${i['workshop'] == true ? ' · workshop bank' : ''}'),
        const SizedBox(height: 12),
        Text('What they wrote', style: Theme.of(context).textTheme.titleSmall),
        SelectionArea(child: Text(i['body'] as String)),
        if (i['can_bring'] != null) Text('Can bring: ${i['can_bring']}'),
        if (i['looking_for'] != null) Text('Looking for: ${i['looking_for']}'),
        if (i['link'] != null) SelectionArea(child: Text('Link: ${i['link']}')),
        const Divider(height: 32),
        Text(i['ai_done_at'] == null ? 'The AI has not read it yet (the lab PC runs it every 15 minutes).' : 'AI version (${i['ai_model']}), editable',
            style: Theme.of(context).textTheme.titleSmall),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: summary, decoration: const InputDecoration(labelText: 'Summary'), maxLines: 3),
        TextField(controller: keywords, decoration: const InputDecoration(labelText: 'Keywords, comma-separated')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            onPressed: () => _set({
              'ai_title': title.text.trim(),
              'ai_summary': summary.text.trim(),
              'ai_keywords': [for (final k in keywords.text.split(',')) if (k.trim().isNotEmpty) k.trim().toLowerCase()],
            }, 'Saved.'),
            child: const Text('Save AI text'),
          ),
          if (i['status'] != 'approved')
            FilledButton.tonal(onPressed: () => _set({'status': 'approved'}, 'Approved: it is matched on the next AI run.'), child: const Text('Approve')),
          if (i['status'] != 'archived') OutlinedButton(onPressed: () => _set({'status': 'archived'}, 'Archived.'), child: const Text('Archive')),
          OutlinedButton(
            onPressed: () => _set({'workshop': !(i['workshop'] as bool)}, i['workshop'] == true ? 'Removed from the workshop bank.' : 'Added to the workshop bank.'),
            child: Text(i['workshop'] == true ? 'Remove from workshops' : 'Workshop bank'),
          ),
          OutlinedButton(onPressed: () => _set({'ai_done_at': null}, 'The AI reads it again on its next run.'), child: const Text('Reprocess')),
        ]),
        const Divider(height: 32),
        Text('Matches (${matches.length})', style: Theme.of(context).textTheme.titleSmall),
        if (matches.isEmpty) const Text('None yet. Matches are made between approved ideas on each AI run.'),
        for (final m in matches)
          Builder(builder: (context) {
            final other = (m['idea_a'] == widget.id ? m['b'] : m['a']) as Rec;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${other['ai_title'] ?? 'An idea'} · ${(other['people'] as Rec)['name']}'),
              subtitle: Text('${m['kind']} ${(m['score'] as num).toStringAsFixed(2)} · ${m['reason']}'
                  '${m['a_connect'] == true && m['b_connect'] == true ? ' · connected' : ''}'),
            );
          }),
        if (past.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Their other ideas (${past.length})', style: Theme.of(context).textTheme.titleSmall),
          for (final x in past) Text('${(x['created_at'] as String).substring(0, 10)} · ${x['status']} · ${x['ai_title'] ?? x['body']}'),
        ],
      ]),
    );
  }
}
