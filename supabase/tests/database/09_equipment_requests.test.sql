begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

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
create temp table tok as select request_equipment('Prof Kit', 'prof.kit@example.com', 'STAFF-7', 'class', 'Physical Computing',
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
select throws_ok($$select request_equipment('X Y', 'x@example.com', 'X-1', 'home', null, now() + interval '1 day', now() + interval '2 days',
  null, jsonb_build_array(jsonb_build_object('item_id', (select laser from t), 'qty', 1)), null)$$,
  'P0001', 'One of the items is not on the list, or its quantity is not 1–100.', 'only lendable items can be asked for');
select throws_ok($$select request_equipment('X Y', 'x@example.com', 'X-1', 'home', null, now() + interval '1 day', now() + interval '2 days',
  now()::date + 30, '[]', 'a soldering iron')$$, 'P0001', 'Weekly repeats are for classes, up to 6 months.', 'only classes repeat');
select throws_ok($$select request_equipment('X Y', 'x@example.com', 'X-1', 'party', null, now() + interval '1 day', now() + interval '2 days',
  null, '[]', 'a soldering iron')$$, 'P0001', null, 'the use must be class, lab or home');
select throws_ok($$select request_equipment('No Number', 'nn@example.com', null, 'lab', null, now() + interval '1 day',
  now() + interval '1 day 2 hours', null, '[]', 'a soldering iron')$$, 'P0001', 'Please give your student number (staff: your staff number).',
                 'the student number is required: it is the lab''s local ID');
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
