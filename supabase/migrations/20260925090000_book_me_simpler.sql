-- Book me, simpler form (2026-09-25): one short line of what the person needs; staff keep their own notes in the office.
create or replace function request_consultation(p_name text, p_email text, p_project text, p_link text, p_starts_at timestamptz,
                                                p_student_number text default null, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_project text := trim(coalesce(p_project, ''));
  v_local   timestamp := p_starts_at at time zone 'Europe/Lisbon';
  v_hours   consultation_hours;
  v_token   uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  perform check_contact(p_name, p_email, p_link, p_student_number);
  if length(v_project) not between 3 and 300 then raise exception 'Say in a line what you need (3–300 characters).'; end if;
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

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status, requester_id, owner_staff_id,
                          purpose, contact_link, status_token)
  values ('Consultation', 'booking', 'consultation', array[v_hours.place_id], p_starts_at,
          p_starts_at + make_interval(mins => v_hours.slot_minutes), 'requested',
          file_student(p_name, p_email, p_student_number), v_hours.staff_id,
          v_project, nullif(trim(coalesce(p_link, '')), ''), v_token);
  return v_token;
end $$;
