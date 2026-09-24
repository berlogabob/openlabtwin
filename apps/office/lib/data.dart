// Every query the office makes. RLS lets only staff (people.is_staff, linked by auth_user_id) read or write.
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logic.dart';

SupabaseClient get db => Supabase.instance.client;

/// Gives up after 20 s instead of leaving a spinner forever (lesson from UNIDCOM RIMS).
class TimeoutClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 20));
}

typedef Rec = Map<String, dynamic>;

/// Reference lists the pages need, loaded once per page.
class Refs {
  Refs(this.places, this.people, this.orgs, this.items, this.me);
  final List<Rec> places, people, orgs, items;
  final int? me; // the signed-in staff member's people.id
  List<Rec> get rooms => [for (final p in places) if (p['kind'] == 'room') p];
  Map<int, String> get itemNames => {for (final i in items) i['id'] as int: i['name'] as String};
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select('id,name,iade_name,kind,tier').order('name'),
    db.from('people').select('id,name,kind,email').order('name'),
    db.from('organizations').select('id,name').order('name'),
    db.from('items').select('id,name,kind').order('name'),
    db.from('people').select('id').eq('auth_user_id', db.auth.currentUser!.id).maybeSingle(),
  ]);
  return Refs(r[0] as List<Rec>, r[1] as List<Rec>, r[2] as List<Rec>, r[3] as List<Rec>, (r[4] as Rec?)?['id'] as int?);
}

/// Upcoming activities, plus repeating ones that started earlier.
Future<List<Activity>> upcoming() async {
  final since = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
  final rows = await db.from('activities').select().or('ends_at.gte.$since,rrule.not.is.null').order('starts_at');
  return [for (final r in rows) Activity.fromRow(r)];
}

Future<int> saveActivity(Activity a) async {
  if (a.id != null) {
    await db.from('activities').update(a.toRow()).eq('id', a.id!);
    return a.id!;
  }
  return (await db.from('activities').insert(a.toRow()).select('id').single())['id'] as int;
}

Future<List<String>> clashWarnings(Activity a, Refs refs) async {
  if (a.placeIds.isEmpty) return _stationaryClashes(a, refs);
  final names = {
    for (final r in refs.rooms)
      if (a.placeIds.contains(r['id'])) (r['iade_name'] ?? r['name']) as String
  };
  final last = a.occurrences().last;
  final lessons = await db
      .from('lessons')
      .select('date,start_time,end_time,course,rooms')
      .gte('date', isoDate(a.start))
      .lte('date', isoDate(last))
      .overlaps('rooms', names.toList());
  final others = await db.from('activities').select().eq('status', 'approved').overlaps('place_ids', a.placeIds);
  return [...clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]), ...await _stationaryClashes(a, refs)];
}

/// The same laser cutter / printer booked by another approved activity at an overlapping time.
Future<List<String>> _stationaryClashes(Activity a, Refs refs) async {
  if (a.id == null) return [];
  final mine = {
    for (final k in await equipment(a.id!))
      if ((k['items'] as Rec)['kind'] == 'stationary') k['item_id'] as int
  };
  if (mine.isEmpty) return [];
  final rows = await db
      .from('activity_items')
      .select('item_id,activities!inner(*)')
      .inFilter('item_id', mine.toList())
      .eq('activities.status', 'approved')
      .neq('activity_id', a.id!);
  final byActivity = <int, (Activity, Set<int>)>{};
  for (final r in rows) {
    final o = Activity.fromRow(r['activities'] as Rec);
    byActivity.putIfAbsent(o.id!, () => (o, <int>{})).$2.add(r['item_id'] as int);
  }
  return equipmentClashes(a, mine, byActivity.values.toList(), refs.itemNames);
}

Future<List<Rec>> equipment(int activityId) =>
    db.from('activity_items').select('item_id,qty,prepared,items(name,kind)').eq('activity_id', activityId).order('item_id');

Future<void> setEquipment(int activityId, int itemId, num qty, bool prepared) => db
    .from('activity_items')
    .upsert({'activity_id': activityId, 'item_id': itemId, 'qty': qty, 'prepared': prepared});

Future<void> removeEquipment(int activityId, int itemId) =>
    db.from('activity_items').delete().eq('activity_id', activityId).eq('item_id', itemId);

Future<Rec> addPerson(String name, String kind, String email) => db
    .from('people')
    .insert({'name': name.trim(), 'kind': kind, 'email': email.trim().isEmpty ? null : email.trim().toLowerCase()})
    .select('id,name,kind,email')
    .single();

Future<Rec> addItem(String name, String kind) =>
    db.from('items').insert({'name': name.trim(), 'kind': kind}).select('id,name,kind').single();

// ---------- inventory ----------

Future<List<Rec>> stock() => db.from('stock').select('item_id,place_id,qty');

Future<List<Rec>> onLoan() => db.from('on_loan').select('item_id,person_id,qty');

/// Movements are append-only: a mistake is corrected with an 'adjust' row, never edited.
Future<void> addMovements(List<Rec> rows) => db.from('movements').insert(rows);

// ---------- book me ----------

Future<List<Rec>> consultationHours() =>
    db.from('consultation_hours').select('id,weekday,from_time,to_time,slot_minutes,places(name),people(name)').order('weekday').order('from_time');

Future<void> addConsultationHours(int staffId, int placeId, int weekday, String from, String to, int slotMinutes) => db
    .from('consultation_hours')
    .insert({'staff_id': staffId, 'place_id': placeId, 'weekday': weekday, 'from_time': from, 'to_time': to, 'slot_minutes': slotMinutes});

Future<void> removeConsultationHours(int id) => db.from('consultation_hours').delete().eq('id', id);

/// Everything a person asked for before: their lab history, newest first.
Future<List<Rec>> history(int personId) => db
    .from('activities')
    .select('id,title,kind,status,starts_at,purpose,contact_link')
    .eq('requester_id', personId)
    .order('starts_at', ascending: false)
    .limit(50);

// ---------- idea hub ----------

Future<List<Rec>> ideas(String status) => db
    .from('ideas')
    .select('id,body,status,workshop,created_at,ai_title,ai_keywords,people(name)')
    .eq('status', status)
    .order('created_at', ascending: false);

Future<Rec> idea1(int id) => db
    .from('ideas')
    .select('id,person_id,body,link,can_bring,looking_for,status,workshop,created_at,ai_title,ai_summary,ai_keywords,ai_model,ai_done_at,'
        'people(name,email,student_number)')
    .eq('id', id)
    .single();

Future<void> updateIdea(int id, Rec change) => db.from('ideas').update(change).eq('id', id);

Future<List<Rec>> ideaMatches(int id) => db
    .from('idea_matches')
    .select('idea_a,idea_b,kind,score,reason,a_connect,b_connect,'
        'a:ideas!idea_matches_idea_a_fkey(id,ai_title,people(name)),b:ideas!idea_matches_idea_b_fkey(id,ai_title,people(name))')
    .or('idea_a.eq.$id,idea_b.eq.$id')
    .order('score', ascending: false);

Future<List<Rec>> personIdeas(int personId) =>
    db.from('ideas').select('id,status,created_at,ai_title,body').eq('person_id', personId).order('created_at', ascending: false);
