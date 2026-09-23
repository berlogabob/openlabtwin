begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into items (name, kind) values ('Loan ESP32', 'portable');
insert into places (name, kind, tier) values ('Loan shelf', 'storage', 'fast');
insert into people (name, kind) values ('Loan student', 'student');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 10, p.id, 'receive' from items i, places p where i.name = 'Loan ESP32' and p.name = 'Loan shelf';
insert into movements (item_id, qty, from_place, person_id, kind)
  select i.id, 5, p.id, s.id, 'issue' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';
insert into movements (item_id, qty, to_place, person_id, kind)
  select i.id, 2, p.id, s.id, 'return' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';

select is((select l.qty from on_loan l join people s on s.id = l.person_id where s.name = 'Loan student'),
          3::numeric, 'issued 5, returned 2: 3 on loan');
select is((select s.qty from stock s join places p on p.id = s.place_id where p.name = 'Loan shelf'),
          7::numeric, 'the shelf holds 10 - 5 + 2');
insert into movements (item_id, qty, to_place, person_id, kind)
  select i.id, 3, p.id, s.id, 'return' from items i, places p, people s
  where i.name = 'Loan ESP32' and p.name = 'Loan shelf' and s.name = 'Loan student';
select is_empty($$select 1 from on_loan l join people s on s.id = l.person_id where s.name = 'Loan student'$$,
                'everything back: nothing on loan');
select throws_ok($$insert into movements (item_id, qty, from_place, kind) select id, 1, null, 'issue' from items where name = 'Loan ESP32'$$,
                 '23514', null, 'an issue needs a place and a person');
set local role anon;
select throws_ok('select * from on_loan', '42501', null, 'anon cannot read on_loan');
reset role;

select * from finish();
rollback;
