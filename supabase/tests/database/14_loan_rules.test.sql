begin;
set local timezone = 'UTC';
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'loan-rules-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Loan rules staff', 'staff', '00000000-0000-0000-0000-0000000000e1', true);
insert into people (name, kind) values ('First borrower', 'student'), ('Second borrower', 'student');
insert into items (name, kind) values ('Loan rules item', 'portable');
insert into places (name, kind, tier) values ('Loan rules shelf', 'storage', 'fast');
insert into assets (item_id, tag) select id, 'LR-001' from items where name = 'Loan rules item';
insert into movements (item_id, asset_id, qty, to_place, kind, at)
  select a.item_id, a.id, 1, p.id, 'receive', '2026-11-17 09:00:00+00'::timestamptz
  from assets a, places p where a.tag = 'LR-001' and p.name = 'Loan rules shelf';

select lives_ok($$insert into movements (item_id, asset_id, qty, from_place, person_id, kind, at)
  select a.item_id, a.id, 1, p.id, s.id, 'issue', '2026-11-17 12:00:00+00'::timestamptz
  from assets a, places p, people s
  where a.tag = 'LR-001' and p.name = 'Loan rules shelf' and s.name = 'First borrower'$$,
  'first issue of a tagged unit succeeds');
select throws_ok($$insert into movements (item_id, asset_id, qty, from_place, person_id, kind)
  select a.item_id, a.id, 1, p.id, s.id, 'issue' from assets a, places p, people s
  where a.tag = 'LR-001' and p.name = 'Loan rules shelf' and s.name = 'Second borrower'$$,
  'P0001', 'LR-001 is already out with First borrower since 2026-11-17',
  'second issue names the tag and current borrower');
select lives_ok($test$do $$begin
  insert into movements (item_id, asset_id, qty, to_place, person_id, kind, at)
    select a.item_id, a.id, 1, p.id, s.id, 'return', '2026-11-17 13:00:00+00'::timestamptz from assets a, places p, people s
    where a.tag = 'LR-001' and p.name = 'Loan rules shelf' and s.name = 'First borrower';
  insert into movements (item_id, asset_id, qty, from_place, person_id, kind, at)
    select a.item_id, a.id, 1, p.id, s.id, 'issue', '2026-11-17 14:00:00+00'::timestamptz from assets a, places p, people s
    where a.tag = 'LR-001' and p.name = 'Loan rules shelf' and s.name = 'Second borrower';
end $$ $test$,
  'return then issue succeeds');
select lives_ok($test$do $$begin
  insert into movements (item_id, qty, from_place, person_id, kind)
    select i.id, 1, p.id, s.id, 'issue' from items i, places p, people s
    where i.name = 'Loan rules item' and p.name = 'Loan rules shelf' and s.name = 'First borrower';
  insert into movements (item_id, qty, from_place, person_id, kind)
    select i.id, 1, p.id, s.id, 'issue' from items i, places p, people s
    where i.name = 'Loan rules item' and p.name = 'Loan rules shelf' and s.name = 'Second borrower';
end $$ $test$,
  'untagged issues are unrestricted');
select throws_ok($test$do $$begin
  insert into movements (item_id, qty, to_place, kind, note)
    select id, 1, (select id from places where name = 'Loan rules shelf'), 'receive', 'tylog:t1:out' from items where name = 'Loan rules item';
  insert into movements (item_id, qty, to_place, kind, note)
    select id, 1, (select id from places where name = 'Loan rules shelf'), 'receive', 'tylog:t1:out' from items where name = 'Loan rules item';
end $$ $test$,
  '23505', null, 'a TyLog step cannot be recorded twice');
select lives_ok($test$do $$begin
  insert into movements (item_id, qty, to_place, kind, note)
    select id, 1, (select id from places where name = 'Loan rules shelf'), 'receive', 'stocktake' from items where name = 'Loan rules item';
  insert into movements (item_id, qty, to_place, kind, note)
    select id, 1, (select id from places where name = 'Loan rules shelf'), 'receive', 'stocktake' from items where name = 'Loan rules item';
end $$ $test$,
  'non-TyLog notes may repeat');

select * from finish();
rollback;
