begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

create temp table tok (who text, t uuid);
insert into tok
  select 'ana', submit_idea('Ana Silva', 'Ana@Example.com', 'A game about growing plants with real sensors', null,
                            'Unity, 3D modelling', 'electronics, soil sensors', 'A-1');
insert into tok
  select 'ben', submit_idea('Ben Costa', 'ben@example.com', 'Plant watering robot for the lab garden', 'https://github.com/ben',
                            'electronics, ESP32', 'someone to make it playful');
insert into tok
  select 'cat', submit_idea('Cat Reis', 'cat@example.com', 'A sound installation for the atrium', null, null, null);
create function pg_temp.st(w text) returns json language sql as $$ select idea_status((select t from tok where who = w)) $$;
create function pg_temp.id(w text) returns bigint language sql as
  $$ select id from ideas where status_token = (select t from tok where who = w) $$;

select ok(has_function_privilege('anon', 'submit_idea(text, text, text, text, text, text, text, text)', 'execute')
          and has_function_privilege('anon', 'idea_status(uuid)', 'execute')
          and has_function_privilege('anon', 'idea_connect(uuid, bigint)', 'execute'), 'anon can call the three idea functions');
select ok(not has_function_privilege('anon', 'file_student(text, text, text)', 'execute')
          and not has_function_privilege('anon', 'check_contact(text, text, text, text)', 'execute'), 'the helpers are not public');
select ok(not has_table_privilege('anon', 'ideas', 'select') and not has_table_privilege('anon', 'idea_matches', 'select')
          and not has_table_privilege('anon', 'idea_skills', 'select'),
          'anon reads no idea table');
select is((select count(*)::int from people where email = 'ana@example.com' and student_number = 'A-1'), 1,
          'the student is filed once, by lowercased email');
select is(pg_temp.st('ana') -> 'idea' ->> 'status', 'new', 'a new idea is new');
select is(pg_temp.st('ana') -> 'idea' ->> 'processed', 'false', 'not processed until the AI job runs');
select is(json_array_length(pg_temp.st('ana') -> 'matches'), 0, 'no matches before approval');
select throws_like($$ select idea_connect((select t from tok where who = 'ana'), pg_temp.id('ben')) $$, '%not approved%',
                   'an unapproved idea cannot connect');

update ideas set status = 'approved' where id in (pg_temp.id('ana'), pg_temp.id('ben'));
insert into idea_matches (idea_a, idea_b, kind, score, reason)
  values (least(pg_temp.id('ana'), pg_temp.id('ben')), greatest(pg_temp.id('ana'), pg_temp.id('ben')), 'complementary', 0.8,
          'one is looking for what the other can bring');
select is(pg_temp.st('ana') -> 'matches' -> 0 ->> 'first_name', 'Ben', 'a match shows the first name');
select ok(pg_temp.st('ana') -> 'matches' -> 0 -> 'contact' is null or (pg_temp.st('ana') -> 'matches' -> 0 ->> 'contact') is null,
          'no contact before both connect');
select lives_ok($$ select idea_connect((select t from tok where who = 'ana'), pg_temp.id('ben')) $$, 'Ana taps connect');
select is(pg_temp.st('ben') -> 'matches' -> 0 ->> 'they_connected', 'true', 'Ben sees that Ana wants to connect');
select idea_connect((select t from tok where who = 'ben'), pg_temp.id('ana'));
select is(pg_temp.st('ana') -> 'matches' -> 0 -> 'contact' ->> 'email', 'ben@example.com', 'both connected: contact shown');
select throws_like($$ select idea_connect((select t from tok where who = 'ana'), pg_temp.id('cat')) $$, '%not available%',
                   'connecting to an unapproved idea is refused');
select throws_like($$ select submit_idea('Ana Silva', 'ana@example.com', 'Idea number six today, too many', null, null, null)
                     from generate_series(1, 5) $$, '%5 ideas today%', 'at most 5 ideas per email per day');

select * from finish();
rollback;
