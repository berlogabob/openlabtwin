begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select ok((select bool_and(relrowsecurity) from pg_class where relname in ('tv_media', 'tv_slides')), 'RLS on both TV tables');
select ok(not has_table_privilege('anon', 'tv_media', 'select') and not has_table_privilege('anon', 'tv_slides', 'select'),
          'anon reads no TV table');
select ok(not has_table_privilege('authenticated', 'tv_media', 'insert')
          and not has_table_privilege('authenticated', 'tv_media', 'delete'), 'only the node (service role) writes tv_media');

insert into tv_media (name, kind, width, height, playable) values ('arm.mp4', 'video', 1920, 1080, true);
insert into tv_slides (kind, title, media_name) values ('media', 'Robot arm', 'arm.mp4');
delete from tv_media where name = 'arm.mp4';
select is((select media_name from tv_slides where title = 'Robot arm'), null, 'a deleted file leaves its slide without media');
select throws_like($$ insert into tv_slides (kind, title) values ('qr', 'No link') $$, '%tv_slides%check%',
                   'a QR slide needs a link');
select throws_like($$ insert into tv_slides (kind, title, starts_on, ends_on) values ('text', 'x', '2026-10-02', '2026-10-01') $$,
                   '%tv_slides%check%', 'the end date is not before the start date');

select lives_ok($$ insert into tv_slides (kind, title) values ('events', 'Upcoming events'), ('ideas', 'Student ideas') $$,
                'the automatic pages are rows too');
select lives_ok($$ insert into tv_slides (kind, title, seconds) values ('text', 'whole', null) $$, 'seconds may be empty (whole video)');
select throws_like($$ insert into tv_slides (kind, title, from_time, to_time) values ('text', 'x', '20:00', '17:00') $$,
                   '%tv_slides_time_order%', 'the end time is after the start time');
select * from finish();
