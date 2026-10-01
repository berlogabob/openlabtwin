-- Bezel gaps for the wall canvas, px hidden behind the monitor frames; set live from the office while the test pattern shows.
alter table wall_state add column bezel jsonb
  check (bezel is null or (jsonb_typeof(bezel -> 'x') = 'number' and jsonb_typeof(bezel -> 'y') = 'number'));
