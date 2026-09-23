-- Core lab data. See docs/superpowers/specs/2026-09-23-openlabtwin-core-design.md, "Data model".

create table places (
  id        bigint generated always as identity primary key,
  name      text not null unique,
  kind      text not null check (kind in ('room', 'storage')),
  tier      text check (tier in ('fast', 'long')),
  parent_id bigint references places (id),
  iade_name text unique,              -- exact room name on the IADE timetable
  public    boolean not null default false,
  check ((kind = 'storage') = (tier is not null))
);

create table items (
  id   bigint generated always as identity primary key,
  name text not null unique,
  kind text not null check (kind in ('consumable', 'portable', 'stationary')),
  unit text not null default 'pcs'
);

create table people (
  id           bigint generated always as identity primary key,
  name         text not null,
  kind         text not null check (kind in ('staff', 'professor', 'student', 'external')),
  email        text unique,
  auth_user_id uuid unique references auth.users (id) on delete set null,
  is_staff     boolean not null default false
);

create table organizations (
  id   bigint generated always as identity primary key,
  name text not null unique,
  kind text not null check (kind in ('club', 'course', 'project'))
);

create table activities (
  id                bigint generated always as identity primary key,
  title             text not null,
  layer             text not null check (layer in ('booking', 'event')),
  kind              text not null check (kind in ('class', 'consultation', 'club', 'workshop', 'equipment', 'maintenance', 'external')),
  place_ids         bigint[] not null default '{}',
  location_text     text,             -- off-site events: no places, a free-text location
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  rrule             text,             -- RFC 5545 RRULE body, e.g. FREQ=WEEKLY;COUNT=10 (UNTIL in local form, no Z)
  exdates           date[] not null default '{}',
  status            text not null default 'requested' check (status in ('requested', 'approved', 'rejected', 'cancelled', 'done')),
  requester_id      bigint references people (id),
  requester_display text,
  owner_staff_id    bigint references people (id),
  organization_id   bigint references organizations (id),
  attendees         int check (attendees >= 0),
  purpose           text,             -- private
  public_note       text,
  created_at        timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table activity_items (
  activity_id bigint not null references activities (id) on delete cascade,
  item_id     bigint not null references items (id),
  qty         numeric not null check (qty > 0),
  prepared    boolean not null default false,
  primary key (activity_id, item_id)
);

create table movements (
  id          bigint generated always as identity primary key,
  item_id     bigint not null references items (id),
  qty         numeric not null,
  from_place  bigint references places (id),
  to_place    bigint references places (id),
  kind        text not null check (kind in ('receive', 'issue', 'return', 'move', 'consume', 'adjust')),
  person_id   bigint references people (id),    -- who holds it (issue / return)
  activity_id bigint references activities (id),
  by_staff    bigint references people (id),
  at          timestamptz not null default now(),
  constraint movement_shape check (case kind
    when 'receive' then from_place is null and to_place is not null and qty > 0
    when 'issue'   then from_place is not null and to_place is null and person_id is not null and qty > 0
    when 'return'  then from_place is null and to_place is not null and person_id is not null and qty > 0
    when 'move'    then from_place is not null and to_place is not null and from_place <> to_place and qty > 0
    when 'consume' then from_place is not null and to_place is null and qty > 0
    when 'adjust'  then from_place is null and to_place is not null and qty <> 0
  end)
);

-- Stock is never stored: it is the sum of movements, per item and place.
create view stock with (security_invoker = true) as
select item_id, place_id, sum(qty) as qty
from (
  select item_id, to_place as place_id, qty from movements where to_place is not null
  union all
  select item_id, from_place, -qty from movements where from_place is not null
) m
group by item_id, place_id;

create table lessons (
  id         bigint generated always as identity primary key,
  hash       text not null unique,       -- sha1 of date|start|end|course|rooms, see scripts/timetable.py
  date       date not null,
  start_time time not null,
  end_time   time not null,
  course     text not null,
  teachers   text[] not null default '{}',
  groups     text[] not null default '{}',
  rooms      text[] not null default '{}',
  type       text not null default '',
  programmes text[] not null default '{}',
  degrees    text[] not null default '{}'
);
create index lessons_date on lessons (date);
