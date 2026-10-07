begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- a clean slate inside this rolled-back transaction: one staff member with hours is the default owner and room
delete from consultation_hours;
create temp table target as
  select (now() at time zone 'Europe/Lisbon')::date + 7 as day;
create function pg_temp.at(t text) returns timestamptz language sql as
  $$ select ((select day from target) + t::time) at time zone 'Europe/Lisbon' $$;
insert into people (name, kind, email, is_staff) values ('Slot staff', 'staff', 'slot-staff@example.com', true);
insert into places (name, kind, iade_name, public) values ('Slot room', 'room', 'Slot Room IADE', true);
insert into consultation_hours (staff_id, place_id, weekday, from_time, to_time)
  select p.id, r.id, 2, '14:00', '17:00'
  from people p, places r where p.email = 'slot-staff@example.com' and r.name = 'Slot room';

select ok(has_function_privilege('anon', 'request_consultation(text, text, text, text, timestamptz, text, text, int)', 'execute'),
          'anon can request a consultation');
select ok(has_function_privilege('anon', 'consultation_status(uuid)', 'execute'), 'anon can read a status by token');
select ok(has_function_privilege('anon', 'answer_proposal(uuid, boolean)', 'execute'), 'anon can answer a proposal by token');
select ok(not has_function_privilege('anon', 'occurs_on(activities, date)', 'execute'), 'the helper is not public');
select ok(not has_table_privilege('anon', 'activities', 'select') and not has_table_privilege('anon', 'consultation_hours', 'select')
          and not has_table_privilege('anon', 'people', 'select'), 'anon still reads no table');

-- any time, no slot list: 07:15 is outside the consultation hours and is accepted
create temp table tok as
  select request_consultation('Ana Test', ' Ana@Example.com ', 'A robot arm for my final project', 'https://example.com/ana',
                              pg_temp.at('07:15'), 'A-123', null, 45) as t;
select is((select status from consultation_status((select t from tok))), 'requested', 'the request is requested, readable by token');
select is((select extract(epoch from ends_at - starts_at)::int from consultation_status((select t from tok))), 2700,
          'the student chose the length');
select is((select owner_staff_id from activities where status_token = (select t from tok)),
          (select id from people where email = 'slot-staff@example.com'), 'the default staff member owns it');
select is((select count(*)::int from people where email = 'ana@example.com' and student_number = 'A-123'), 1,
          'the student is filed by lowercased email with the student number');

-- staff propose another time; the student accepts
update activities set status = 'proposed', proposed_starts_at = pg_temp.at('15:00'), proposed_ends_at = pg_temp.at('15:30')
 where status_token = (select t from tok);
select is((select proposed_starts_at from consultation_status((select t from tok))), pg_temp.at('15:00'), 'the status shows the proposal');
select lives_ok($$ select answer_proposal((select t from tok), true) $$, 'the student accepts');
select results_eq($$ select status, starts_at, proposed_starts_at from consultation_status((select t from tok)) $$,
                  $$ values ('approved'::text, pg_temp.at('15:00'), null::timestamptz) $$, 'accepting moves and approves it');
select throws_like($$ select answer_proposal((select t from tok), false) $$, '%no proposal%', 'a settled request has nothing to answer');

select lives_ok($$ select request_consultation('Ana Test', 'ana@example.com', 'A second visit, same project', null, pg_temp.at('16:00'), 'A-123') $$,
                'a second open request by the same student is accepted');
select lives_ok($$ select request_consultation('Ana Test', 'ana@example.com', 'A third visit is fine now', null, pg_temp.at('17:00'), 'A-123') $$,
                'an approved request no longer counts as open');
select throws_like($$ select request_consultation('Ana Test', 'ana@example.com', 'A fourth is too many', null, pg_temp.at('18:00'), 'A-123') $$,
                   '%2 open requests%', 'a third open request by the same email is refused');
select throws_like($$ select request_consultation('Cat Test', 'cat@example.com', 'hi', null, pg_temp.at('10:00'), 'C-1') $$, '%3–300%',
                   'the request needs at least a short line');
select throws_like($$ select request_consultation('Dan Test', 'dan@example.com', 'Right now please', null, now(), 'D-1') $$, '%an hour%',
                   'a time in the past or within the hour is refused');
-- only the student number is required: name, email and the line are optional
select lives_ok($$ select request_consultation(null, null, null, null, pg_temp.at('10:00'), 'E-77') $$, 'only the student number is needed');
select is((select p.email from activities a join people p on p.id = a.requester_id where p.student_number = 'E-77'), 'e-77@iade.pt',
          'no email: the number plus @iade.pt');
select is((select p.name from activities a join people p on p.id = a.requester_id where p.student_number = 'E-77'), 'E-77',
          'no name: the number stands in');
select throws_like($$ select request_consultation('Fay', 'fay@example.com', null, null, pg_temp.at('10:30'), '') $$, '%student number%',
                   'the student number is still required');
select * from finish();
rollback;
