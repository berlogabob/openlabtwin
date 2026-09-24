begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

-- a clean slate inside this rolled-back transaction: only our test hours count
delete from consultation_hours;
create temp table target as
  select (now() at time zone 'Europe/Lisbon')::date + 7 as day;   -- same weekday next week: inside the 14-day window
create function pg_temp.at(t text) returns timestamptz language sql as
  $$ select ((select day from target) + t::time) at time zone 'Europe/Lisbon' $$;
insert into people (name, kind, email, is_staff) values ('Slot staff', 'staff', 'slot-staff@example.com', true);
insert into places (name, kind, iade_name, public) values ('Slot room', 'room', 'Slot Room IADE', true);
insert into consultation_hours (staff_id, place_id, weekday, from_time, to_time)
  select p.id, r.id, extract(isodow from (select day from target)), '14:00', '17:00'
  from people p, places r where p.email = 'slot-staff@example.com' and r.name = 'Slot room';
insert into lessons (hash, date, start_time, end_time, course, rooms)
  values ('slot-lesson', (select day from target), '14:00', '14:30', 'Busy lesson', array['Slot Room IADE']);
insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status)
  select 'Busy booking', 'booking', 'class', array[r.id], pg_temp.at('15:00'), pg_temp.at('15:30'), 'requested'
  from places r where r.name = 'Slot room';

select ok(has_function_privilege('anon', 'free_slots(date, date)', 'execute'), 'anon can list free slots');
select ok(has_function_privilege('anon', 'request_consultation(text, text, text, text, timestamptz, text, text)', 'execute'),
          'anon can request a consultation');
select ok(has_function_privilege('anon', 'consultation_status(uuid)', 'execute'), 'anon can read a status by token');
select ok(not has_function_privilege('anon', 'occurs_on(activities, date)', 'execute'), 'the helper is not public');
select ok(not has_table_privilege('anon', 'activities', 'select') and not has_table_privilege('anon', 'consultation_hours', 'select')
          and not has_table_privilege('anon', 'people', 'select'), 'anon still reads no table');

select results_eq(
  $$ select to_char(starts_at at time zone 'Europe/Lisbon', 'HH24:MI') from free_slots((select day from target), (select day from target)) $$,
  array['14:30', '15:30', '16:00', '16:30'], 'free slots skip the lesson (14:00) and the requested booking (15:00)');

create temp table tok as
  select request_consultation('Ana Test', ' Ana@Example.com ', 'A robot arm for my final project', 'https://example.com/ana',
                              pg_temp.at('14:30'), 'A-123') as t;
select is((select status from consultation_status((select t from tok))), 'requested', 'the request is requested, readable by token');
select is((select count(*)::int from people where email = 'ana@example.com' and student_number = 'A-123'), 1,
          'the student is filed by lowercased email with the student number');
select results_eq(
  $$ select to_char(starts_at at time zone 'Europe/Lisbon', 'HH24:MI') from free_slots((select day from target), (select day from target)) $$,
  array['15:30', '16:00', '16:30'], 'a requested slot is no longer free');
select throws_like($$ select request_consultation('Ben', 'ben@example.com', 'Another project idea', null, pg_temp.at('14:30')) $$,
                   '%no longer free%', 'the same slot twice is refused');
select lives_ok($$ select request_consultation('Ana Test', 'ana@example.com', 'A second visit, same project', null, pg_temp.at('15:30')) $$,
                'a second open request by the same student is accepted');
select throws_like($$ select request_consultation('Ana Test', 'ana@example.com', 'A third one is too many', null, pg_temp.at('16:00')) $$,
                   '%2 open requests%', 'a third open request by the same email is refused');
select is((select count(*)::int from people where email = 'ana@example.com'), 1, 'repeat requests share one people row: one history');
select is((select count(*)::int from activities a join people p on p.id = a.requester_id where p.email = 'bot@example.com'), 0,
          'honeypot writes nothing')
  from (select request_consultation('Bot', 'bot@example.com', 'Spam spam spam spam', null, pg_temp.at('16:30'), null, 'http://x')) h;

select * from finish();
rollback;
