begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'archive-staff@example.com');
insert into people (name, kind, auth_user_id, is_staff) values ('Archive staff', 'staff', '00000000-0000-0000-0000-0000000000e1', true);
insert into people (name, kind, student_number) values ('Archive student', 'student', 'A-20190001'), ('Other student', 'student', 'A-20190002');
insert into items (name, kind) values ('Arch Arduino Uno', 'portable'), ('Arch Kinect', 'portable');
insert into places (name, kind, tier, code) values ('Arch shelf', 'storage', 'fast', 'ARCH-S1');
insert into movements (item_id, qty, to_place, kind) select id, 2, (select id from places where code = 'ARCH-S1'), 'receive'
  from items where name = 'Arch Arduino Uno';
insert into archive_sheets (sha256, file_name, extracted, status) values ('sha-test-1', 'sheet1.jpg', '{"name": "Archive student"}', 'extracted');

set local role anon;
select throws_ok('select * from archive_sheets', '42501', null, 'anon cannot read the archive');
select throws_ok('select * from usage_by_item', '42501', null, 'anon cannot read usage');
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select is((select name from match_item('arduino uno') limit 1), 'Arch Arduino Uno', 'a line from a sheet finds its item');
select lives_ok($$select approve_sheet((select id from archive_sheets where sha256 = 'sha-test-1'), jsonb_build_array(
  jsonb_build_object('person_id', (select id from people where name = 'Archive student'), 'course', 'Design 2',
                     'item_id', (select id from items where name = 'Arch Arduino Uno'), 'item_text', 'Arduino UNO', 'qty', 2,
                     'out_on', '2019-03-01', 'back_on', '2019-03-20'),
  jsonb_build_object('person_id', (select id from people where name = 'Archive student'), 'course', 'Design 2',
                     'item_id', null, 'item_text', 'caixa de fios', 'qty', 1, 'out_on', '2019-03-01', 'back_on', null)))$$,
                'staff approve a sheet with its lines');
reset role;

select is((select status from archive_sheets where sha256 = 'sha-test-1'), 'reviewed', 'the sheet is marked reviewed');
select is((select reviewed_by from archive_sheets where sha256 = 'sha-test-1'), (select id from people where name = 'Archive staff'),
          'by the staff member who approved it');
select is((select count(*)::int from archive_loans l join archive_sheets s on s.id = l.sheet_id where s.sha256 = 'sha-test-1'), 2,
          'both lines kept, the unmatched one too');
select is((select sum(qty) from stock s join items i on i.id = s.item_id where i.name = 'Arch Arduino Uno'), 2::numeric,
          'historic loans never change stock');
select is((select units from usage_by_item u where u.name = 'Arch Arduino Uno' and u.source = 'archive'), 2::numeric,
          'usage counts the archive loan');

-- another student had the other 2 Arduinos at the same time: the lab ran out
insert into archive_sheets (sha256, file_name, status) values ('sha-test-2', 'sheet2.jpg', 'reviewed');
insert into archive_loans (sheet_id, person_id, item_id, item_text, qty, out_on, back_on)
  select s.id, p.id, i.id, 'arduino', 2, '2019-03-10', '2019-03-12' from archive_sheets s, people p, items i
  where s.sha256 = 'sha-test-2' and p.name = 'Other student' and i.name = 'Arch Arduino Uno';
select is((select peak::int || '/' || owned::int from peak_on_loan where name = 'Arch Arduino Uno'), '4/2',
          'peak out at once against owned: a candidate to buy');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
select lives_ok($$select merge_items((select id from items where name = 'Arch Arduino Uno'), array[(select id from items where name = 'Arch Kinect')])$$,
                'staff merge two items');
reset role;
select is((select count(*)::int from archive_loans l join items i on i.id = l.item_id where i.name = 'Arch Kinect'), 0,
          'merging items moves their historic loans too');

select * from finish();
rollback;
