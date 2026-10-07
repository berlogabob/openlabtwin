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
  Refs(this.places, this.people, this.orgs, this.items, this.assets, this.me);
  final List<Rec> places, people, orgs, items, assets;
  final int? me; // the signed-in staff member's people.id
  List<Rec> get rooms => [for (final p in places) if (p['kind'] == 'room') p];
  Map<int, String> get itemNames => {for (final i in items) i['id'] as int: i['name'] as String};
  Rec? placeByCode(String code) => places.where((p) => p['code'] == code).firstOrNull;
  String placeName(int? id) {
    final p = places.where((p) => p['id'] == id).firstOrNull;
    return p == null ? '?' : (p['code'] == null ? p['name'] as String : '${p['code']} · ${p['name']}');
  }
}

Future<Refs> loadRefs() async {
  final r = await Future.wait([
    db.from('places').select(placeCols).order('name'),
    db.from('people').select('id,name,kind,email').order('name'),
    db.from('organizations').select('id,name').order('name'),
    db.from('items').select('id,name,kind,note,lendable').isFilter('merged_into', null).order('name'),
    db.from('assets').select('id,item_id,tag,serial,condition').order('tag'),
    db.from('people').select('id').eq('auth_user_id', db.auth.currentUser!.id).maybeSingle(),
  ]);
  return Refs(r[0] as List<Rec>, r[1] as List<Rec>, r[2] as List<Rec>, r[3] as List<Rec>, r[4] as List<Rec>, (r[5] as Rec?)?['id'] as int?);
}

const placeCols = 'id,name,iade_name,kind,tier,parent_id,code,counted_at';

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

/// Lessons on [day] (YYYY-MM-DD) that bear on a consultation: in the lab rooms, and of the staff member's own master
/// programme (they study there). Private: office only.
Future<List<Rec>> dayLessons(String day, List<String> roomNames) async {
  final rows = await db
      .from('lessons')
      .select('start_time,end_time,course,rooms,programmes')
      .eq('date', day)
      .or('rooms.ov.{${roomNames.map((r) => '"$r"').join(',')}},programmes.cs.{"$myProgramme"}')
      .order('start_time');
  return [for (final r in rows) r];
}

/// The programme the lab's staff member studies (the master's), as it appears in the timetable.
const myProgramme = 'Mestrado em Computação Criativa e Inteligência Artificial';

Future<List<String>> clashWarnings(Activity a, Refs refs) async {
  if (a.placeIds.isEmpty) return [...await _stationaryClashes(a, refs), ...await _demand(a, refs)];
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
  return [
    ...clashes(a, names, lessons, [for (final o in others) Activity.fromRow(o)]),
    ...await _stationaryClashes(a, refs),
    ...await _demand(a, refs),
  ];
}

/// Portable kit lines that, with overlapping approved bookings, ask for more than the lab owns.
Future<List<String>> _demand(Activity a, Refs refs) async {
  if (a.id == null) return [];
  final mine = {
    for (final k in await equipment(a.id!))
      if ((k['items'] as Rec)['kind'] != 'stationary') k['item_id'] as int: k['qty'] as num
  };
  if (mine.isEmpty) return [];
  final rows = await db
      .from('activity_items')
      .select('item_id,qty,activities!inner(*)')
      .inFilter('item_id', mine.keys.toList())
      .eq('activities.status', 'approved')
      .neq('activity_id', a.id!);
  final byActivity = <int, (Activity, Map<int, num>)>{};
  for (final r in rows) {
    final o = Activity.fromRow(r['activities'] as Rec);
    byActivity.putIfAbsent(o.id!, () => (o, <int, num>{})).$2[r['item_id'] as int] = r['qty'] as num;
  }
  final totals = <int, num>{};
  for (final s in await stock()) {
    final item = s['item_id'] as int;
    if (mine.containsKey(item)) totals[item] = (totals[item] ?? 0) + (s['qty'] as num);
  }
  return demandWarnings(a, mine, byActivity.values.toList(), totals, refs.itemNames);
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

/// A new portable item can be requested on the public /kit/ list straight away; staff can switch that off.
Future<Rec> addItem(String name, String kind) => db
    .from('items')
    .insert({'name': name.trim(), 'kind': kind, 'lendable': kind == 'portable'})
    .select('id,name,kind,note,lendable')
    .single();

// ---------- inventory ----------

Future<List<Rec>> stock() => db.from('stock').select('item_id,place_id,qty');

Future<List<Rec>> onLoan() => db.from('on_loan').select('item_id,person_id,qty');

/// Movements are append-only: a mistake is corrected with an 'adjust' row, never edited.
Future<void> addMovements(List<Rec> rows) => db.from('movements').insert(rows);

// ---------- smart storage ----------

/// Where each tagged item is now (its latest movement): place_id, or person_id while on loan.
Future<List<Rec>> assetPlaces() => db.from('asset_place').select('asset_id,place_id,person_id');

/// Everything in Needs attention (view storage_issues), waived ones already left out.
Future<List<Rec>> storageIssues() => db.from('storage_issues').select('code,a_id,b_id,detail,key').order('code').order('detail');

Future<Rec> savePlace(Rec row, int? id) => id == null
    ? db.from('places').insert(row).select(placeCols).single()
    : db.from('places').update(row).eq('id', id).select(placeCols).single();

Future<void> markCounted(int placeId) =>
    db.from('places').update({'counted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', placeId);

Future<Rec> addAsset(int itemId, String tag, String serial) => db
    .from('assets')
    .insert({'item_id': itemId, if (tag.trim().isNotEmpty) 'tag': tag.trim(), 'serial': serial.trim().isEmpty ? null : serial.trim()})
    .select('id,item_id,tag,serial,condition')
    .single();

/// Whether the public /kit/ list offers this item.
Future<void> setLendable(int itemId, bool lendable) => db.from('items').update({'lendable': lendable}).eq('id', itemId);

Future<void> updateAssets(List<int> ids, Rec change) => db.from('assets').update(change).inFilter('id', ids);

Future<void> waiveIssue(String key, int? staffId) => db.from('issue_waivers').insert({'key': key, 'by_staff': staffId});

/// Soft merge (merge_items): the losers' stock, tagged items and kit lines move to the survivor; the losers stay, hidden.
Future<void> mergeItems(int survivor, List<int> losers) => db.rpc('merge_items', params: {'p_survivor': survivor, 'p_losers': losers});

// ---------- paper loan archive ----------

Future<List<Rec>> archiveSheets() => db
    .from('archive_sheets')
    .select('id,file_name,image_path,photo_at,raw_text,extracted,status,error,created_at')
    .order('id');

Future<String> archiveImageUrl(String path) => db.storage.from('archive').createSignedUrl(path, 3600);

Future<List<Rec>> matchItem(String text) async => [for (final r in await db.rpc('match_item', params: {'p_text': text}) as List) r as Rec];

Future<void> approveSheet(int id, List<Rec> loans) => db.rpc('approve_sheet', params: {'p_sheet': id, 'p_loans': loans});

Future<void> setStudentNumber(int personId, String number) => db.from('people').update({'student_number': number}).eq('id', personId);

Future<void> rejectSheet(int id) => db.from('archive_sheets').update({'status': 'rejected'}).eq('id', id);

Future<List<Rec>> usageByItem() => db.from('usage_by_item').select();
Future<List<Rec>> usageByCourse() => db.from('usage_by_course').select();
Future<List<Rec>> peakOnLoan() => db.from('peak_on_loan').select();

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

Future<List<TvSlide>> tvSlides() async =>
    [for (final r in await db.from('tv_slides').select().order('position').order('id')) TvSlide.fromRow(r)];

/// Approved events and bookings from yesterday on, to link TV pages to.
Future<List<Rec>> tvEvents() async => await db
    .from('activities')
    .select('id,title,layer,starts_at,ends_at')
    .eq('status', 'approved')
    .gte('ends_at', DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String())
    .order('starts_at')
    .limit(100);

/// The edge node's heartbeat for the TV (one row), or null before its first run.
Future<Rec?> tvStatus() async => await db.from('tv_status').select().maybeSingle();

/// The files the edge node reported from its shared TV folder.
Future<List<Rec>> tvMedia() async => await db.from('tv_media').select('name,kind,playable,seconds').order('name');

Future<void> saveTvSlide(TvSlide s) async {
  if (s.id == null) {
    await db.from('tv_slides').insert(s.toRow());
  } else {
    await db.from('tv_slides').update(s.toRow()).eq('id', s.id!);
  }
}

Future<void> deleteTvSlide(int id) async => await db.from('tv_slides').delete().eq('id', id);

Future<void> reorderTvSlides(List<int> ids) async =>
    await Future.wait([for (var i = 0; i < ids.length; i++) db.from('tv_slides').update({'position': i}).eq('id', ids[i])]);

Future<List<WallSlide>> wallSlides() async =>
    [for (final r in await db.from('wall_slides').select().order('position').order('id')) WallSlide.fromRow(r)];

/// The office's controls for the wall (one row): blackout, playing, sleep window, "show now".
Future<Rec?> wallState() async => await db.from('wall_state').select().maybeSingle();

/// The wall server's heartbeat (one row), or null before its first report.
Future<Rec?> wallStatus() async => await db.from('wall_status').select().maybeSingle();

Future<String> wallPreviewUrl() => db.storage.from('wall-preview').createSignedUrl('current.jpg', 60);

Future<void> setWallState(Rec fields) async => await db.from('wall_state').update(fields).eq('id', 1);

Future<void> saveWallSlide(WallSlide s) async {
  if (s.id == null) {
    await db.from('wall_slides').insert(s.toRow());
  } else {
    await db.from('wall_slides').update(s.toRow()).eq('id', s.id!);
  }
}

Future<void> deleteWallSlide(int id) async => await db.from('wall_slides').delete().eq('id', id);

Future<void> reorderWallSlides(List<int> ids) async =>
    await Future.wait([for (var i = 0; i < ids.length; i++) db.from('wall_slides').update({'position': i}).eq('id', ids[i])]);
