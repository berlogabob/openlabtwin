-- "Book me": consultation requests by QR (docs/superpowers/specs/2026-09-24-book-me-design.md).
-- The only write path open to anonymous visitors is request_consultation(); it validates everything itself.

create table consultation_hours (
  id           bigint generated always as identity primary key,
  staff_id     bigint not null references people (id),
  place_id     bigint not null references places (id),
  weekday      int not null check (weekday between 1 and 7),   -- ISO: 1 = Monday
  from_time    time not null,
  to_time      time not null,
  slot_minutes int not null default 30 check (slot_minutes between 10 and 240),
  check (to_time > from_time)
);
alter table consultation_hours enable row level security;
create policy staff_all on consultation_hours for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on consultation_hours for each row execute function audit();
revoke all on consultation_hours from anon;

alter table activities add column status_token uuid unique, add column contact_link text;
alter table people add column student_number text unique;

-- Does activity a occur on local date d? One-off, or weekly (FREQ=WEEKLY;UNTIL=YYYYMMDD…, what the office writes).
create function occurs_on(a activities, d date) returns boolean
language sql stable set search_path = public as $$
  select case
    when a.rrule is null then (a.starts_at at time zone 'Europe/Lisbon')::date = d
    else extract(isodow from d) = extract(isodow from a.starts_at at time zone 'Europe/Lisbon')
         and d >= (a.starts_at at time zone 'Europe/Lisbon')::date
         and d <= coalesce(to_date(substring(a.rrule from 'UNTIL=(\d{8})'), 'YYYYMMDD'), d)
         and not d = any (a.exdates)
  end
$$;

-- Free consultation slots, today .. today + 14, starting at least 1 hour from now, in Lisbon wall-clock time.
create function free_slots(p_from date, p_to date)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  with days as (
    select g::date as d
    from generate_series(greatest(p_from, (now() at time zone 'Europe/Lisbon')::date),
                         least(p_to, (now() at time zone 'Europe/Lisbon')::date + 14), interval '1 day') g
  ), slots as (
    select h.place_id, days.d, t.local_start, t.local_start + make_interval(mins => h.slot_minutes) as local_end
    from consultation_hours h
    join days on extract(isodow from days.d) = h.weekday
    cross join lateral generate_series(days.d + h.from_time, days.d + h.to_time - make_interval(mins => h.slot_minutes),
                                       make_interval(mins => h.slot_minutes)) as t (local_start)
  )
  select distinct s.local_start at time zone 'Europe/Lisbon', s.local_end at time zone 'Europe/Lisbon'
  from slots s
  where s.local_start at time zone 'Europe/Lisbon' >= now() + interval '1 hour'
    and not exists (
      select 1 from lessons l join places p on p.id = s.place_id
      where l.date = s.d and p.iade_name = any (l.rooms)
        and l.start_time < s.local_end::time and s.local_start::time < l.end_time)
    and not exists (
      select 1 from activities a
      where a.status in ('requested', 'approved') and s.place_id = any (a.place_ids) and occurs_on(a, s.d)
        and (a.starts_at at time zone 'Europe/Lisbon')::time < s.local_end::time
        and s.local_start::time < (a.ends_at at time zone 'Europe/Lisbon')::time)
  order by 1
$$;

-- A student's request. Returns the private status token. ponytail: two simultaneous requests for one slot can both
-- land; staff approve one. Add a unique slot constraint if that ever happens.
create function request_consultation(p_name text, p_email text, p_project text, p_link text, p_starts_at timestamptz,
                                     p_student_number text default null, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_name    text := trim(coalesce(p_name, ''));
  v_project text := trim(coalesce(p_project, ''));
  v_link    text := nullif(trim(coalesce(p_link, '')), '');
  v_number  text := nullif(trim(coalesce(p_student_number, '')), '');
  v_local   timestamp := p_starts_at at time zone 'Europe/Lisbon';
  v_hours   consultation_hours;
  v_person  bigint;
  v_token   uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  if length(v_name) not between 2 and 100 then raise exception 'Please give your name (2–100 characters).'; end if;
  if length(v_email) not between 3 and 200 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please give a valid email.'; end if;
  if length(v_project) not between 10 and 2000 then raise exception 'Describe your project in 10–2000 characters.'; end if;
  if v_link is not null and (length(v_link) > 500 or v_link !~* '^https?://\S+$') then
    raise exception 'The link must start with http:// or https://.'; end if;
  if v_number is not null and v_number !~ '^[A-Za-z0-9-]{1,30}$' then
    raise exception 'The student number can only have letters, digits and dashes.'; end if;
  if not exists (select 1 from free_slots(v_local::date, v_local::date) f where f.starts_at = p_starts_at) then
    raise exception 'That time is no longer free. Please pick another.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'consultation' and a.status = 'requested' and p.email = v_email) >= 2 then
    raise exception 'You already have 2 open requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'consultation' and status = 'requested') >= 20 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  select h.* into v_hours from consultation_hours h
   where h.weekday = extract(isodow from v_local)
     and v_local::time >= h.from_time and v_local::time + make_interval(mins => h.slot_minutes) <= h.to_time
   order by h.id limit 1;

  insert into people (name, kind, email, student_number) values (v_name, 'student', v_email, v_number)
  on conflict (email) do update
    set name = case when people.kind = 'student' then excluded.name else people.name end,
        student_number = coalesce(excluded.student_number, people.student_number)
  returning id into v_person;

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status, requester_id, owner_staff_id,
                          purpose, contact_link, status_token)
  values ('Consultation', 'booking', 'consultation', array[v_hours.place_id], p_starts_at,
          p_starts_at + make_interval(mins => v_hours.slot_minutes), 'requested', v_person, v_hours.staff_id,
          v_project, v_link, v_token);
  return v_token;
end $$;

-- What the student's private link shows: status and time, nothing else.
create function consultation_status(p_token uuid)
returns table (status text, starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.status, a.starts_at, a.ends_at from activities a where a.status_token = p_token and a.kind = 'consultation'
$$;

revoke all on function occurs_on(activities, date) from public, anon, authenticated;
revoke all on function free_slots(date, date), consultation_status(uuid),
  request_consultation(text, text, text, text, timestamptz, text, text) from public;
grant execute on function free_slots(date, date), consultation_status(uuid),
  request_consultation(text, text, text, text, timestamptz, text, text) to anon, authenticated;
