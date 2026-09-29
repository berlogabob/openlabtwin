begin;
create extension if not exists pgtap with schema extensions;
select plan(2);

select lives_ok($$ insert into tv_slides (kind, title, seconds, every_seconds) values ('text', 'Notice', 10, 30) $$,
                'a page can interrupt every 30 s for 10 s');
select throws_like($$ insert into tv_slides (kind, title, seconds, every_seconds) values ('text', 'x', 10, 10) $$,
                   '%tv_slides_every%', 'the gap is longer than the page stays');
select * from finish();
rollback;
