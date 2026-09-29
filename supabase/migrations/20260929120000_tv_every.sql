-- Announcements: a page with every_seconds leaves the loop and interrupts the TV every that many seconds, for its own
-- seconds (full screen or the pages area, by fullscreen). Only inside its dates and times, like any page.
alter table tv_slides
  add column every_seconds int,
  add constraint tv_slides_every check (every_seconds is null or every_seconds > coalesce(seconds, 0));
