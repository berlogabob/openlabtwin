begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'storage-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Storage staff', 'staff', '00000000-0000-0000-0000-0000000000c1', true);
insert into people (name, kind) values ('Storage student', 'student');
insert into items (name, kind) values ('Test Quest', 'portable'), ('Test cable', 'consumable');
insert into places (name, kind, tier, code) values ('Test shelf', 'storage', 'fast', 'T-S1');
insert into assets (item_id, serial) select id, 'SN-TEST-1' from items where name = 'Test Quest';

select throws_ok($$insert into places (name, kind, tier, code) values ('Bad', 'storage', 'fast', 'r15 left')$$,
                 '23514', null, 'a code is capitals, digits and dashes');
select matches((select tag from assets where serial = 'SN-TEST-1'), '^TL-[0-9]{4}$', 'an untagged asset gets the next TL number');
select lives_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select a.item_id, a.id, 1, p.id, 'receive' from assets a, places p where a.serial = 'SN-TEST-1' and p.code = 'T-S1'$$,
                'an asset is received one at a time');
select throws_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select a.item_id, a.id, 2, p.id, 'receive' from assets a, places p where a.serial = 'SN-TEST-1' and p.code = 'T-S1'$$,
                 '23514', null, 'an asset movement has quantity 1');
select throws_ok($$insert into movements (item_id, asset_id, qty, to_place, kind)
  select i.id, a.id, 1, p.id, 'receive' from assets a, items i, places p
  where a.serial = 'SN-TEST-1' and i.name = 'Test cable' and p.code = 'T-S1'$$,
                 '23503', null, 'an asset moves only as its own item');
select is((select p.code from asset_place ap join assets a on a.id = ap.asset_id join places p on p.id = ap.place_id
           where a.serial = 'SN-TEST-1'), 'T-S1', 'received: the asset is on the shelf');
insert into movements (item_id, asset_id, qty, from_place, person_id, kind)
  select a.item_id, a.id, 1, p.id, s.id, 'issue' from assets a, places p, people s
  where a.serial = 'SN-TEST-1' and p.code = 'T-S1' and s.name = 'Storage student';
select is((select s.name from asset_place ap join assets a on a.id = ap.asset_id join people s on s.id = ap.person_id
           where a.serial = 'SN-TEST-1' and ap.place_id is null), 'Storage student', 'issued: the student holds it');
insert into movements (item_id, asset_id, qty, to_place, person_id, kind)
  select a.item_id, a.id, 1, p.id, s.id, 'return' from assets a, places p, people s
  where a.serial = 'SN-TEST-1' and p.code = 'T-S1' and s.name = 'Storage student';
select is((select p.code from asset_place ap join assets a on a.id = ap.asset_id join places p on p.id = ap.place_id
           where a.serial = 'SN-TEST-1'), 'T-S1', 'returned: back on the shelf');

set local role anon;
select throws_ok('select * from assets', '42501', null, 'anon cannot read assets');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select lives_ok($$insert into assets (item_id) select id from items where name = 'Test cable'$$, 'staff add assets (tag from the sequence)');
reset role;

select * from finish();
rollback;
