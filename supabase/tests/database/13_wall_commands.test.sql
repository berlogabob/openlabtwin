begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select lives_ok($$ update wall_state set command = '{"kind": "restart", "code": "a1", "at": "2026-10-02T10:00:00Z"}' $$,
                'a per-screen restart command is valid');
select lives_ok($$ update wall_state set command = '{"kind": "reboot", "code": "all", "at": "2026-10-02T10:01:00Z"}' $$,
                'a reboot-all command is valid');
select throws_like($$ update wall_state set command = '{"kind": "identify", "code": "a1", "at": "2026-10-02T10:00:00Z"}' $$,
                   '%check%', 'unknown commands are rejected');
select throws_like($$ update wall_state set command = '{"code": "a1", "at": "2026-10-02T10:00:00Z"}' $$,
                   '%check%', 'commands need a kind');
select throws_like($$ update wall_state set command = '{"kind": "reboot", "at": "2026-10-02T10:00:00Z"}' $$,
                   '%check%', 'commands need a screen code');
select * from finish();
rollback;
