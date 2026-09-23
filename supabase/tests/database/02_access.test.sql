begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'staff@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'someone@example.com');
insert into people (name, kind, email, auth_user_id, is_staff)
  values ('Staff', 'staff', 'staff@example.com', '00000000-0000-0000-0000-00000000000a', true);
insert into lessons (hash, date, start_time, end_time, course) values ('h1', '2026-10-01', '09:00', '10:00', 'X');

set local role anon;
select throws_ok('select * from lessons', '42501', null, 'anon cannot read lessons');
select throws_ok('select * from people', '42501', null, 'anon cannot read people');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
select is_empty('select * from people', 'signed-in non-staff sees no people');
select throws_ok($$insert into items (name, kind) values ('Hack', 'portable')$$, '42501', null, 'non-staff cannot write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select isnt_empty('select * from lessons', 'staff reads lessons');
select lives_ok($$insert into items (name, kind) values ('Audited ESP32', 'portable')$$, 'staff writes items');
select throws_ok('delete from movements', '42501', null, 'movements are append-only for staff');
reset role;

select is((select count(*)::int from audit_log where table_name = 'items' and op = 'INSERT'
           and new_row ->> 'name' = 'Audited ESP32'), 1, 'item insert is audited');

select * from finish();
rollback;
