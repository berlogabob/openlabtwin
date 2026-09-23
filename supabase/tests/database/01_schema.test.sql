begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into items (name, kind) values ('Test ESP32', 'portable');
insert into places (name, kind, tier) values ('Test long', 'storage', 'long'), ('Test fast', 'storage', 'fast');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 30, p.id, 'receive' from items i, places p where i.name = 'Test ESP32' and p.name = 'Test long';
insert into movements (item_id, qty, from_place, to_place, kind)
  select i.id, 12, l.id, f.id, 'move' from items i, places l, places f
  where i.name = 'Test ESP32' and l.name = 'Test long' and f.name = 'Test fast';

select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Test long'),
          18::numeric, 'move takes stock out of the source');
select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Test fast'),
          12::numeric, 'move puts stock into the target');
select throws_ok($$insert into movements (item_id, qty, kind) select id, 1, 'receive' from items where name = 'Test ESP32'$$,
                 '23514', null, 'receive without a target place is rejected');
select throws_ok($$insert into places (name, kind) values ('Test shelf', 'storage')$$,
                 '23514', null, 'storage needs a tier');

select * from finish();
rollback;