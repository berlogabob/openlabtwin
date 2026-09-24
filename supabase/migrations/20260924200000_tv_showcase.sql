-- TV showcase: the edge node's media files and the staff's carousel slides. Staff only, like the other tables.

create table tv_media (   -- written by the node (scripts/tv.py) every minute
  name     text primary key,
  kind     text not null check (kind in ('video', 'photo')),
  width    int,
  height   int,
  seconds  numeric,
  bytes    bigint not null default 0,
  playable boolean not null default false
);

create table tv_slides (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('media', 'bio', 'qr', 'text')),
  title      text,
  body       text,
  media_name text references tv_media (name) on delete set null on update cascade,
  url        text,
  seconds    int not null default 10 check (seconds > 0),
  position   int not null default 0,
  starts_on  date,
  ends_on    date,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  check (kind <> 'qr' or url is not null),
  check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

-- ponytail: tv_media is not audited; the node rewrites it every minute and the files themselves are the record.
create trigger audit after insert or update or delete on tv_slides for each row execute function audit();

alter table tv_media enable row level security;
alter table tv_slides enable row level security;
create policy staff_all on tv_media for all to authenticated using (is_staff()) with check (is_staff());
create policy staff_all on tv_slides for all to authenticated using (is_staff()) with check (is_staff());
revoke all on tv_media, tv_slides from anon;
revoke insert, update, delete, truncate on tv_media from authenticated;
