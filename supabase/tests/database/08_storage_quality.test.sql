begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000d1', 'quality-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Quality staff', 'staff', '00000000-0000-0000-0000-0000000000d1', true);
insert into items (name, kind) values ('Comandos PS4 Brancos', 'portable'), ('Comando PS4 branco', 'portable'), ('Laser cutter', 'stationary');
insert into places (name, kind, tier, code) values ('Quality shelf', 'storage', 'fast', 'Q-S1');
insert into movements (item_id, qty, to_place, kind)
  select i.id, 3, p.id, 'receive' from items i, places p where i.name = 'Comandos PS4 Brancos' and p.code = 'Q-S1';
insert into movements (item_id, qty, to_place, kind)
  select i.id, 2, p.id, 'receive' from items i, places p where i.name = 'Comando PS4 branco' and p.code = 'Q-S1';

select isnt_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%'$$,
                  'near-identical names are flagged');
select is_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like '%Laser%'$$, 'different names are not');
select isnt_empty($$select 1 from storage_issues s join places p on p.id = s.a_id where s.code = 'never_counted' and p.code = 'Q-S1'$$,
                  'a shelf with stock and no count needs attention');
insert into issue_waivers (key) select key from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%';
select is_empty($$select 1 from storage_issues where code = 'possible_duplicate' and detail like 'Comandos PS4 Brancos%'$$,
                'a waived issue stops showing');
select throws_ok($$select merge_items(1, array[2::bigint])$$, 'P0001', 'Only lab staff can merge items.', 'only staff merge');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select lives_ok($$select merge_items((select id from items where name = 'Comandos PS4 Brancos'),
                                     array[(select id from items where name = 'Comando PS4 branco')])$$, 'staff merge duplicates');
reset role;

select is((select s.qty from stock s join places p on p.id = s.place_id join items i on i.id = s.item_id
           where p.code = 'Q-S1' and i.name = 'Comandos PS4 Brancos'), 5::numeric, 'the survivor holds both counts');
select is((select merged_into is not null from items where name = 'Comando PS4 branco'), true, 'the duplicate stays, marked merged');

select * from finish();
rollback;