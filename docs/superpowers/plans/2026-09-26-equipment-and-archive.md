# Equipment requests and the paper loan archive: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Files go to local pi on **Unsloth Studio** (`PI_PROVIDER=studio PI_MODEL=unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`) through `pi_task.py` ("create or replace file = block", time-boxed, anything unfinished is written from the plan). The controller runs every shell step and all verification.

**Spec:** `docs/superpowers/specs/2026-09-26-equipment-and-archive-design.md`.

## Ponytail

- One public form for every kind of request (class, lab work, take home); the use is a field, not three forms.
- The catalogue is names only; availability stays a staff decision (the office's demand warning).
- Historic loans live in their own table; they never touch stock.

---

### Task 1: Equipment requests in the database

- [ ] **Step 1 (pi): create `supabase/tests/database/09_equipment_requests.test.sql`**

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into items (name, kind, lendable) values ('Kit ESP32', 'portable', true), ('Kit laser cutter', 'stationary', false);
create temp table t as select now() + interval '2 days' as s, (select id from items where name = 'Kit laser cutter') as laser;
grant select on t to anon;

select ok(has_function_privilege('anon', 'equipment_catalogue()', 'execute')
          and has_function_privilege('anon', 'request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text)', 'execute')
          and has_function_privilege('anon', 'equipment_status(uuid)', 'execute'), 'anon can list, request and read a status');
select ok(not has_table_privilege('anon', 'items', 'select') and not has_table_privilege('anon', 'stock', 'select'),
          'anon still reads no table');
select is((select count(*)::int from equipment_catalogue() where name = 'Kit ESP32'), 1, 'lendable items are listed');
select is((select count(*)::int from equipment_catalogue() where name = 'Kit laser cutter'), 0, 'items not lent are not');

set local role anon;
create temp table tok as select request_equipment('Prof Kit', 'prof.kit@example.com', null, 'class', 'Physical Computing',
  (select s from t), (select s from t) + interval '2 hours', ((select s from t) + interval '28 days')::date,
  jsonb_build_array(jsonb_build_object('item_id', (select id from equipment_catalogue() where name = 'Kit ESP32'), 'qty', 12)),
  'and a projector adapter') as token;
reset role;

select is((select kind || ' ' || status || ' ' || title from activities where status_token = (select token from tok)),
          'equipment requested Class kit', 'a request is a requested equipment booking');
select is((select qty from activity_items k join activities a on a.id = k.activity_id join items i on i.id = k.item_id
           where a.status_token = (select token from tok) and i.name = 'Kit ESP32'), 12::numeric, 'with its kit filled in');
select matches((select rrule from activities where status_token = (select token from tok)), '^FREQ=WEEKLY;UNTIL=\d{8}T235959$',
               'a class can repeat weekly');
select matches((select purpose from activities where status_token = (select token from tok)),
               'For a class: Physical Computing.*projector adapter', 'use, course and the free text land in purpose');
select is((select items -> 0 ->> 'name' from equipment_status((select token from tok))), 'Kit ESP32', 'the status link lists the items');

set local role anon;
select throws_ok($$select request_equipment('X Y', 'x@example.com', null, 'home', null, now() + interval '1 day', now() + interval '2 days',
  null, jsonb_build_array(jsonb_build_object('item_id', (select laser from t), 'qty', 1)), null)$$,
  'P0001', 'One of the items is not on the list, or its quantity is not 1–100.', 'only lendable items can be asked for');
select throws_ok($$select request_equipment('X Y', 'x@example.com', null, 'home', null, now() + interval '1 day', now() + interval '2 days',
  now()::date + 30, '[]', 'a soldering iron')$$, 'P0001', 'Weekly repeats are for classes, up to 6 months.', 'only classes repeat');
select throws_ok($$select request_equipment('X Y', 'x@example.com', null, 'party', null, now() + interval '1 day', now() + interval '2 days',
  null, '[]', 'a soldering iron')$$, 'P0001', null, 'the use must be class, lab or home');
select isnt((select request_equipment('Bot', 'bot@example.com', null, 'home', null, now(), now(), null, '[]', null, 'http://spam')), null,
            'the honeypot answers with a token');
reset role;
select is((select count(*)::int from people where email = 'bot@example.com'), 0, '… and stores nothing');

-- a kit issued for a booking that ended two days ago and never came back
insert into places (name, kind, tier, code) values ('Kit shelf', 'storage', 'fast', 'KIT-S1');
insert into activities (title, layer, kind, starts_at, ends_at, status)
  values ('Old workshop', 'booking', 'workshop', now() - interval '3 days', now() - interval '2 days', 'approved');
insert into movements (item_id, qty, to_place, kind) select id, 5, (select id from places where code = 'KIT-S1'), 'receive' from items where name = 'Kit ESP32';
insert into movements (item_id, qty, from_place, person_id, activity_id, kind)
  select i.id, 3, p.id, (select id from people where email = 'prof.kit@example.com'), a.id, 'issue'
  from items i, places p, activities a where i.name = 'Kit ESP32' and p.code = 'KIT-S1' and a.title = 'Old workshop';
select isnt_empty($$select 1 from storage_issues where code = 'kit_not_returned' and detail like 'Old workshop%3 not returned'$$,
                  'a kit still out after its booking is in Needs attention');

select * from finish();
rollback;
```

- [ ] **Step 2 (controller):** `uv run python scripts/sqltest.py` → `09_equipment_requests` fails (function `equipment_catalogue` does not exist).

- [ ] **Step 3 (pi): create `supabase/migrations/20260926120000_equipment_requests.sql`**

```sql
-- Equipment requests (docs/superpowers/specs/2026-09-26-equipment-and-archive-design.md): anyone with an email can ask for
-- equipment for a class, lab work or to take home. It lands as a requested 'equipment' booking with its kit filled in;
-- staff approve, prepare and issue it as any other kit. Asking is optional everywhere: no booking needs a kit.

-- Which items the public list offers. Portable ones by default; staff untick what isn't lent.
alter table items add column lendable boolean not null default false;
update items set lendable = true where kind = 'portable' and merged_into is null;

-- The public catalogue: names only. Places, counts and tags never leave the database this way.
create function equipment_catalogue() returns table (id bigint, name text, kind text)
language sql stable security definer set search_path = public as $$
  select id, name, kind from items where lendable and merged_into is null order by name
$$;

-- p_use: class | lab | home. p_items: [{"item_id": 12, "qty": 3}, ...]. p_repeat_until: weekly, classes only.
create function request_equipment(p_name text, p_email text, p_student_number text, p_use text, p_course text,
                                  p_starts_at timestamptz, p_ends_at timestamptz, p_repeat_until date, p_items jsonb,
                                  p_other text, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email  text := lower(trim(coalesce(p_email, '')));
  v_other  text := trim(coalesce(p_other, ''));
  v_course text := trim(coalesce(p_course, ''));
  v_items  jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]' end;
  v_day    date := (p_starts_at at time zone 'Europe/Lisbon')::date;
  v_token  uuid := gen_random_uuid();
  v_id     bigint;
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  perform check_contact(p_name, p_email, null, p_student_number);
  if coalesce(p_use, '') not in ('class', 'lab', 'home') then
    raise exception 'Say what it is for: a class, lab work or taking it home.'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then raise exception 'The end must be after the start.'; end if;
  if p_starts_at < now() - interval '1 hour' or p_starts_at > now() + interval '180 days' then
    raise exception 'Pick a date from today up to 6 months ahead.'; end if;
  if p_ends_at > p_starts_at + interval '90 days' then raise exception 'Ask for at most 90 days at a time.'; end if;
  if p_repeat_until is not null and (p_use <> 'class' or p_repeat_until < v_day or p_repeat_until > v_day + 180) then
    raise exception 'Weekly repeats are for classes, up to 6 months.'; end if;
  if jsonb_array_length(v_items) > 20 then raise exception 'At most 20 different items per request.'; end if;
  if jsonb_array_length(v_items) = 0 and length(v_other) < 3 then raise exception 'Pick at least one item, or say what you need.'; end if;
  if length(v_other) > 500 or length(v_course) > 100 then
    raise exception 'Keep "something else" under 500 characters and the course under 100.'; end if;
  if exists (select 1 from jsonb_array_elements(v_items) e
             where case when jsonb_typeof(e -> 'item_id') = 'number' and jsonb_typeof(e -> 'qty') = 'number'
                        then (e ->> 'qty')::numeric not between 1 and 100
                             or not exists (select 1 from items i where i.id = (e ->> 'item_id')::bigint and i.lendable and i.merged_into is null)
                        else true end) then
    raise exception 'One of the items is not on the list, or its quantity is not 1–100.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'equipment' and a.status = 'requested' and a.status_token is not null and p.email = v_email) >= 3 then
    raise exception 'You already have 3 open equipment requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'equipment' and status = 'requested' and status_token is not null) >= 30 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, rrule, status, requester_id, purpose, status_token)
  values (case p_use when 'class' then 'Class kit' when 'lab' then 'Lab work' else 'Take-home kit' end,
          'booking', 'equipment',
          case when p_use = 'lab' then coalesce((select array[id] from places where code = 'LAB'), '{}') else '{}' end,
          p_starts_at, p_ends_at,
          case when p_repeat_until is not null then 'FREQ=WEEKLY;UNTIL=' || to_char(p_repeat_until, 'YYYYMMDD') || 'T235959' end,
          'requested', file_student(p_name, p_email, p_student_number),
          concat_ws(E'\n', case p_use when 'class' then 'For a class' when 'lab' then 'Lab work' else 'To take home' end
                              || coalesce(': ' || nullif(v_course, ''), ''),
                    nullif(v_other, '')),
          v_token)
  returning id into v_id;
  insert into activity_items (activity_id, item_id, qty)
    select v_id, (e ->> 'item_id')::bigint, sum((e ->> 'qty')::numeric) from jsonb_array_elements(v_items) e group by 1, 2;
  return v_token;
end $$;

-- What the private link shows: status, dates, the items asked for (names only).
create function equipment_status(p_token uuid)
returns table (status text, starts_at timestamptz, ends_at timestamptz, rrule text, items jsonb)
language sql stable security definer set search_path = public as $$
  select a.status, a.starts_at, a.ends_at, a.rrule,
         coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'qty', k.qty) order by i.name)
                   from activity_items k join items i on i.id = k.item_id where k.activity_id = a.id), '[]')
  from activities a where a.status_token = p_token and a.kind = 'equipment'
$$;

revoke all on function equipment_catalogue(), equipment_status(uuid),
  request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) from public;
grant execute on function equipment_catalogue(), equipment_status(uuid),
  request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) to anon, authenticated;

-- Needs attention gains kits that weren't brought back.
create or replace view storage_issues with (security_invoker = true) as
select * from (
  select 'negative_stock' as code, s.item_id as a_id, s.place_id as b_id,
         i.name || ': ' || s.qty || ' at ' || p.name as detail, 'neg:' || s.item_id || ':' || s.place_id as key
  from stock s join items i on i.id = s.item_id join places p on p.id = s.place_id
  where s.qty < 0
  union all
  select 'never_counted', p.id, null, p.name || ' has never been counted', 'count:' || p.id
  from places p
  where p.counted_at is null and exists (select 1 from stock s where s.place_id = p.id and s.qty <> 0)
  union all
  select 'stale_count', p.id, null, p.name || ' last counted ' || to_char(p.counted_at, 'YYYY-MM-DD'),
         'stale:' || p.id || ':' || to_char(p.counted_at, 'YYYYMMDD')
  from places p
  where p.counted_at < now() - interval '180 days'
  union all
  select 'possible_duplicate', a.id, b.id, a.name || ' / ' || b.name, 'dup:' || a.id || ':' || b.id
  from items a join items b on a.id < b.id
  where a.merged_into is null and b.merged_into is null and extensions.similarity(a.name_norm, b.name_norm) > 0.5
  union all
  select 'asset_' || x.condition, x.id, x.item_id, i.name || ' ' || x.tag || ' is ' || x.condition, 'asset:' || x.id || ':' || x.condition
  from assets x join items i on i.id = x.item_id
  where x.condition <> 'ok'
  union all
  -- a booking's kit still out a day after the booking ended (a repeating one: a day after the session of its last issue)
  select 'kit_not_returned', k.activity_id, null,
         a.title || ' (' || to_char(a.starts_at at time zone 'Europe/Lisbon', 'YYYY-MM-DD') || '): ' || k.n_out || ' not returned',
         'kit:' || k.activity_id
  from (select activity_id, sum(case kind when 'issue' then qty else -qty end) as n_out,
               max(at) filter (where kind = 'issue') as last_issue
        from movements where activity_id is not null and kind in ('issue', 'return') group by activity_id) k
  join activities a on a.id = k.activity_id
  where k.n_out > 0
    and case when a.rrule is null then a.ends_at else k.last_issue + (a.ends_at - a.starts_at) end < now() - interval '1 day'
) issue
where key not in (select key from issue_waivers);
```

- [ ] **Step 4 (controller):** `uv run python scripts/sqltest.py` → ✓ for every file, 09 with 15 passed.

- [ ] **Commit:** "Equipment requests: public catalogue, request and status functions, overdue kits in Needs attention"

---

### Task 2: The /kit/ request form

- [ ] **Step 1 (pi): create `apps/site/lib/kit.dart`**

```dart
// Equipment requests (/kit/): the catalogue search, the form's checks (mirroring request_equipment()) and what it sends.
import 'book.dart';
import 'schedule.dart' show plain;

const uses = {'class': 'For my class', 'lab': 'Lab work in the Tech Lab', 'home': 'To take home'};

typedef Item = ({int id, String name});

List<Item> catalogue(List<Object?> rows) =>
    [for (final r in rows.cast<Map<String, dynamic>>()) (id: r['id'] as int, name: r['name'] as String)];

/// Items whose name holds every typed word, ignoring case and accents: "esp dev" finds "ESP32 DevKit".
List<Item> search(List<Item> items, String q) {
  final words = [for (final w in plain(q).split(RegExp(r'\s+'))) if (w.isNotEmpty) w];
  return [for (final i in items) if (words.every(plain(i.name).contains)) i];
}

/// A local date ("2026-10-20") and time ("14:00") as an instant, or null when either is missing.
DateTime? localAt(String date, String time) => date.isEmpty || time.isEmpty ? null : DateTime.tryParse('${date}T$time');

/// The first problem with the form, or null. Same rules as request_equipment() in the database.
String? kitProblem({
  required String name,
  required String email,
  String number = '',
  required String use,
  DateTime? start,
  DateTime? end,
  String repeatUntil = '',
  required Map<int, int> picked,
  String other = '',
  String course = '',
}) {
  final contact = contactProblem(name: name, email: email, number: number);
  if (contact != null) return contact;
  if (!uses.containsKey(use)) return 'Say what it is for: a class, lab work or taking it home.';
  if (start == null || end == null) return 'Pick the date and times.';
  if (!end.isAfter(start)) return 'The end must be after the start.';
  if (end.difference(start).inDays > 90) return 'Ask for at most 90 days at a time.';
  if (repeatUntil.isNotEmpty && use != 'class') return 'Weekly repeats are for classes, up to 6 months.';
  if (picked.length > 20) return 'At most 20 different items per request.';
  if (picked.isEmpty && other.trim().length < 3) return 'Pick at least one item, or say what you need.';
  if (picked.values.any((q) => q < 1 || q > 100)) return 'Quantities are 1–100.';
  if (other.trim().length > 500 || course.trim().length > 100) {
    return 'Keep "something else" under 500 characters and the course under 100.';
  }
  return null;
}

/// The arguments of request_equipment().
Map<String, Object?> requestArgs({
  required String name,
  required String email,
  String number = '',
  required String use,
  String course = '',
  required DateTime start,
  required DateTime end,
  String repeatUntil = '',
  required Map<int, int> picked,
  String other = '',
  String website = '',
}) =>
    {
      'p_name': name,
      'p_email': email,
      'p_student_number': number,
      'p_use': use,
      'p_course': course,
      'p_starts_at': start.toUtc().toIso8601String(),
      'p_ends_at': end.toUtc().toIso8601String(),
      'p_repeat_until': repeatUntil.isEmpty ? null : repeatUntil,
      'p_items': [for (final e in picked.entries) {'item_id': e.key, 'qty': e.value}],
      'p_other': other,
      'p_website': website,
    };
```

- [ ] **Step 2 (pi): create `apps/site/lib/pages/kit_page.dart`**

```dart
// Equipment request form (/kit/): who, what for (class, lab work, take home), when, and a checklist from the lab's
// catalogue. Optional everywhere else: a booking never needs one. Ends with the private status link, as Book me does.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../book.dart';
import '../calendar.dart';
import '../kit.dart';

@client
class KitPage extends StatefulComponent {
  const KitPage({super.key});

  @override
  State<KitPage> createState() => KitPageState();
}

class KitPageState extends State<KitPage> {
  List<Item>? items;
  final picked = <int, int>{};
  String name = '', email = '', number = '', use = 'class', course = '', other = '', website = '', q = '';
  String day = iso(DateTime.now().add(const Duration(days: 1))), from = '10:00', to = '12:00', backDay = '', until = '';
  String? error, token;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await rpc('equipment_catalogue', {}) as List;
      setState(() => items = catalogue(rows));
    } catch (e) {
      setState(() => error = 'Could not load the equipment list: $e');
    }
  }

  // a take-home loan is picked up and brought back on two days; a class or lab work is one time slot
  DateTime? get _start => use == 'home' ? localAt(day, '10:00') : localAt(day, from);
  DateTime? get _end => use == 'home' ? localAt(backDay, '18:00') : localAt(day, to);

  Future<void> _send() async {
    final problem = kitProblem(
        name: name, email: email, number: number, use: use, start: _start, end: _end,
        repeatUntil: use == 'class' ? until : '', picked: picked, other: other, course: course);
    if (problem != null) return setState(() => error = problem);
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final t = await rpc('request_equipment', requestArgs(
          name: name, email: email, number: number, use: use, course: course, start: _start!, end: _end!,
          repeatUntil: use == 'class' ? until : '', picked: picked, other: other, website: website));
      setState(() => token = t as String);
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      setState(() => sending = false);
    }
  }

  Component _field(String caption, String value, void Function(String) set, {InputType type = InputType.text}) =>
      label([.text(caption), input<String>(type: type, value: value, onInput: (v) => setState(() => set(v)))]);

  Component _item(Item i) {
    final n = picked[i.id];
    return div(classes: 'kit-item', [
      button(
        type: ButtonType.button,
        classes: n == null ? 'slot' : 'slot on',
        onClick: () => setState(() => n == null ? picked[i.id] = 1 : picked.remove(i.id)),
        [.text(i.name)],
      ),
      if (n != null)
        label([
          .text('How many'),
          input<String>(
            type: InputType.text,
            value: '$n',
            attributes: {'inputmode': 'numeric', 'size': '3'},
            onInput: (v) => setState(() => picked[i.id] = int.tryParse(v.trim()) ?? 0),
          ),
        ]),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final link = token == null ? '' : Uri.base.resolve('status/?t=$token').toString();
    final shown = items == null ? const <Item>[] : search(items!, q);
    return div(classes: 'book', [
      header([
        h1([a(href: './', [.text('Ask for equipment')])]),
        nav([a(href: '../', [.text('Schedule')])]),
      ]),
      main_([
        if (token != null)
          section(classes: 'done', [
            h2([.text('Request sent')]),
            p([.text('The lab prepares it once approved. Bookmark this private link to follow it:')]),
            p([a(href: link, [.text(link)])]),
          ])
        else ...[
          p([.text('Tell the Tech Lab what you need for a class, for lab work, or to take home for a project.')]),
          div(classes: 'slots', [
            for (final e in uses.entries)
              button(type: ButtonType.button, classes: use == e.key ? 'slot on' : 'slot', onClick: () => setState(() => use = e.key),
                  [.text(e.value)]),
          ]),
          div(classes: 'form', [
            if (use == 'home') ...[
              _field('Pick up on', day, (v) => day = v, type: InputType.date),
              _field('Bring back on', backDay, (v) => backDay = v, type: InputType.date),
            ] else ...[
              _field('Day', day, (v) => day = v, type: InputType.date),
              _field('From', from, (v) => from = v, type: InputType.time),
              _field('To', to, (v) => to = v, type: InputType.time),
              if (use == 'class') _field('Every week until (optional)', until, (v) => until = v, type: InputType.date),
            ],
            _field(use == 'class' ? 'Class or course' : 'Course or project (optional)', course, (v) => course = v),
          ]),
          h2([.text('What you need')]),
          if (items == null && error == null) p(classes: 'empty', [.text('Loading the equipment list…')]),
          if (items != null) ...[
            div(classes: 'form', [_field('Search', q, (v) => q = v)]),
            div(classes: 'kit-list', [for (final i in shown) _item(i)]),
            if (shown.isEmpty) p(classes: 'empty', [.text('Nothing by that name. Describe it below.')]),
          ],
          div(classes: 'form', [
            label([.text('Something else, or details (optional)'), textarea(rows: 3, onInput: (v) => other = v, [.text(other)])]),
            _field('Name', name, (v) => name = v),
            _field('Email', email, (v) => email = v, type: InputType.email),
            _field('Student number (optional)', number, (v) => number = v),
            // honeypot: hidden from people, bots fill it in
            label(classes: 'hp', attributes: {'aria-hidden': 'true'}, [
              .text('Website'),
              input<String>(type: InputType.text, value: website, attributes: {'tabindex': '-1', 'autocomplete': 'off'}, onInput: (v) => website = v),
            ]),
            p(classes: 'note', [.text('${picked.length} item${picked.length == 1 ? '' : 's'} picked.')]),
            button(type: ButtonType.button, disabled: sending, onClick: _send, [.text(sending ? 'Sending…' : 'Send request')]),
            if (error != null) p(classes: 'error', [.text(error!)]),
            p(classes: 'note', [.text('Your request is saved in your lab history, visible to lab staff only.')]),
          ]),
        ],
      ]),
    ]);
  }
}
```

- [ ] **Step 3 (pi): create `apps/site/lib/pages/kit_status_page.dart`**

```dart
// Equipment request status (/kit/status/?t=…): what the private link shows. Its own file: one @client component per file.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

import '../book.dart';
import '../calendar.dart';

String _time(DateTime d) => '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

@client
class KitStatusPage extends StatefulComponent {
  const KitStatusPage({super.key});

  @override
  State<KitStatusPage> createState() => KitStatusPageState();
}

class KitStatusPageState extends State<KitStatusPage> {
  String? message;
  List<String> lines = [];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _load();
  }

  Future<void> _load() async {
    final t = Uri.parse(web.window.location.href).queryParameters['t'] ?? '';
    try {
      final rows = t.isEmpty ? const [] : await rpc('equipment_status', {'p_token': t}) as List;
      if (rows.isEmpty) return setState(() => message = 'No request found for this link.');
      final r = rows.first as Map<String, dynamic>;
      final start = DateTime.parse(r['starts_at'] as String).toLocal(), end = DateTime.parse(r['ends_at'] as String).toLocal();
      final when = iso(start) == iso(end)
          ? '${dayName(iso(start))}, ${_time(start)}–${_time(end)}'
          : '${dayName(iso(start))} to ${dayName(iso(end))}';
      setState(() {
        message = '${statusLabels[r['status']] ?? r['status']} · $when${r['rrule'] == null ? '' : ' · every week'}';
        lines = [for (final i in (r['items'] as List).cast<Map<String, dynamic>>()) '${i['qty']} × ${i['name']}'];
      });
    } catch (e) {
      setState(() => message = 'Could not load the status: $e');
    }
  }

  @override
  Component build(BuildContext context) => div(classes: 'book', [
        header([h1([a(href: '../', [.text('Your equipment request')])])]),
        main_([
          p(classes: 'status', [.text(message ?? 'Loading…')]),
          if (lines.isNotEmpty) ul([for (final l in lines) li([.text(l)])]),
        ]),
      ]);
}
```

- [ ] **Step 4 (controller):** routes `/kit` and `/kit/status` in `apps/site/lib/app.dart`, a "Need equipment?" link on the Book me page, `.kit-list` styles, the QR `apps/site/web/qr/kit.svg` (segno), and tests in `apps/site/test/logic_test.dart`. Then `cd apps/site && dart analyze && dart test && jaspr build`.

- [ ] **Commit:** "Site: /kit/ equipment request form and its private status page"

---
