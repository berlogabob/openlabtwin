-- Setup checks from the office: {"kind": "identify" | "test", "code": "a1" | "all", "until": timestamptz}.
-- The wall server shows it on those screens until "until", above everything else (someone is at the wall).
alter table wall_state add column overlay jsonb
  check (overlay is null or (overlay ->> 'kind' in ('identify', 'test') and overlay ? 'code' and overlay ? 'until'));
