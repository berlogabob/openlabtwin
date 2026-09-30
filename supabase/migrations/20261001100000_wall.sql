-- Video wall (github.com/berlogabob/videowall): the wall server on the edge node polls wall_state and wall_slides
-- every 2 s and writes wall_status every 10 s. Staff edit the playlist and the controls in the office.
-- wall_slides uses the TV's schedule columns (dates, times of day, takeover, every_seconds, activity_id), so the same
-- event plays on the TV and the wall in the same slot.

create table wall_slides (
  id            bigint generated always as identity primary key,
  mode          text not null check (mode in ('mosaic', 'videowall')),
  title         text,
  media_names   text[] not null default '{}',   -- videowall: exactly 1 file; mosaic: files spread over the screens, {} = all
  seconds       int check (seconds > 0),         -- null: a videowall video plays to its end (stills 10 s, mosaic 30 s)
  cycle_seconds int check (cycle_seconds > 0),   -- mosaic: each screen moves to the next file this often
  fit           text not null default 'fit' check (fit in ('fit', 'fill', 'center')),
  show_title    boolean not null default false,  -- draw the title on the canvas (videowall)
  credits       text,
  logo          boolean not null default false,
  matte         int not null default 0 check (matte between 0 and 400),  -- black frame, px of the canvas
  position      int not null default 0,
  active        boolean not null default true,
  starts_on     date,
  ends_on       date,
  from_time     time,
  to_time       time,
  takeover      boolean not null default false,
  every_seconds int,
  activity_id   bigint references activities (id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint wall_slides_one_file check (mode <> 'videowall' or cardinality(media_names) = 1),
  constraint wall_slides_dates check (starts_on is null or ends_on is null or ends_on >= starts_on),
  constraint wall_slides_time_order check (from_time is null or to_time is null or to_time > from_time),
  constraint wall_slides_every check (every_seconds is null or every_seconds > coalesce(seconds, 0))
);

create table wall_state (   -- the office's controls, one row
  id        int primary key default 1 check (id = 1),
  blackout  boolean not null default false,
  playing   boolean not null default true,       -- false: stopped, the wall shows the logo or black
  now       jsonb check (now is null or now ->> 'mode' in ('mosaic', 'videowall')),  -- "show this now", a slide-shaped object
  now_at    timestamptz,                         -- synced start of "now"
  now_until timestamptz                          -- null: until "Back to schedule"
);
insert into wall_state default values;

create table wall_status (  -- the wall server's heartbeat, one row
  id           int primary key default 1 check (id = 1),
  seen_at      timestamptz,
  playing      text,
  screens      jsonb not null default '{}',     -- {"a1": {"on": true, "throttled": "0x0", "drift_ms": 12, ...}}
  slides       jsonb not null default '{}',     -- {"12": "ready" | "rendering 40%" | "failed: ..."}
  cache_mb     int,
  disk_free_mb int,
  error        text,
  error_at     timestamptz
);

create trigger audit after insert or update or delete on wall_slides for each row execute function audit();
create trigger audit after insert or update or delete on wall_state for each row execute function audit();

alter table wall_slides enable row level security;
alter table wall_state enable row level security;
alter table wall_status enable row level security;
create policy staff_all on wall_slides for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_read on wall_state for select to authenticated using (is_staff());
create policy staff_update on wall_state for update to authenticated using (is_staff()) with check (is_staff());
create policy staff_read on wall_status for select to authenticated using (is_staff());
revoke all on wall_slides, wall_state, wall_status from anon;
revoke insert, delete, truncate on wall_state from authenticated;
revoke insert, update, delete, truncate on wall_status from authenticated;
