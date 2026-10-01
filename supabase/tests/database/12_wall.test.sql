begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

select ok((select bool_and(relrowsecurity) from pg_class where relname in ('wall_slides', 'wall_state', 'wall_status')),
          'RLS on the three wall tables');
select ok(not has_table_privilege('anon', 'wall_slides', 'select') and not has_table_privilege('anon', 'wall_state', 'select')
          and not has_table_privilege('anon', 'wall_status', 'select'), 'anon reads no wall table');
select ok(not has_table_privilege('authenticated', 'wall_status', 'update')
          and not has_table_privilege('authenticated', 'wall_status', 'insert'), 'only the wall server writes its heartbeat');
select ok(not has_table_privilege('authenticated', 'wall_state', 'insert')
          and has_table_privilege('authenticated', 'wall_state', 'update'), 'staff change the one control row, never add one');
select is((select count(*)::int from wall_state), 1, 'the control row exists');
select throws_like($$ insert into wall_slides (mode, media_names) values ('videowall', '{a.mp4,b.mp4}') $$,
                   '%wall_slides_one_file%', 'a videowall slide shows exactly one file');
select lives_ok($$ insert into wall_slides (mode, media_names) values ('mosaic', '{}') $$, 'a mosaic of every file');
select throws_like($$ insert into wall_slides (mode, media_names, seconds, every_seconds) values ('videowall', '{a.jpg}', 20, 10) $$,
                   '%wall_slides_every%', 'an announcement gap is longer than its seconds');
select throws_like($$ insert into wall_slides (mode, media_names, from_time, to_time) values ('mosaic', '{}', '20:00', '17:00') $$,
                   '%wall_slides_time_order%', 'the end time is after the start time');
select throws_like($$ insert into wall_slides (mode, fit) values ('mosaic', 'stretch') $$, '%check%', 'fit is fit, fill or center');
select lives_ok($$ update wall_state set overlay = '{"kind": "identify", "code": "all", "until": "2026-10-01T10:00:00Z"}' $$,
                'the office can ask for Identify on every screen');
select throws_like($$ update wall_state set overlay = '{"kind": "reboot", "code": "a1", "until": "x"}' $$, '%check%',
                   'only identify or test');
select * from finish();
