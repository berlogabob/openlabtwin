-- A TV page can be linked to a schedule event (or booking): it then plays exactly during that activity's time slot,
-- whatever its own dates and times say. If the activity is cancelled or deleted, the page stops playing.
alter table tv_slides add column activity_id bigint references activities (id) on delete set null;
