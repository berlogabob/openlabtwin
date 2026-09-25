-- Event mode: a page can have a time window, fill the whole screen, and take the TV over.
-- While any takeover page is inside its dates and times, the TV plays only the takeover pages.
alter table tv_slides
  add column from_time  time,
  add column to_time    time,
  add column fullscreen boolean not null default false,
  add column takeover   boolean not null default false,
  add constraint tv_slides_time_order check (from_time is null or to_time is null or to_time > from_time);
