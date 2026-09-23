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

/// Reference lists the form needs, loaded once per page.
class Refs {
  Refs(this.rooms, this.people, this.orgs, this.items, this.me);
  final List<Rec> rooms, people, orgs, items;
  final int? me; // the signed-in staff member's people.id
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select('id,name,iade_name').eq('kind', 'room').order('name'),
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
  if (a.placeIds.isEmpty) return [];
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
  return clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]);
}

Future<List<Rec>> equipment(int activityId) =>
    db.from('activity_items').select('item_id,qty,prepared,items(name)').eq('activity_id', activityId).order('item_id');

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
