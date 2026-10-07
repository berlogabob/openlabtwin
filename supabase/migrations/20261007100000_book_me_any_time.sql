-- Book me, any time (decision 0048): a student asks for any date and time; staff accept it or propose another time,
-- which the student confirms on the private status link. free_slots() stays but the site no longer uses it.

alter table activities drop constraint activities_status_check;
alter table activities add constraint activities_status_check
  check (status in ('requested', 'proposed', 'approved', 'rejected', 'cancelled', 'done'));
alter table activities add column proposed_starts_at timestamptz, add column proposed_ends_at timestamptz;

drop function request_consultation(text, text, text, text, timestamptz, text, text);
create function request_consultation(p_name text, p_email text, p_project text, p_link text, p_starts_at timestamptz,
                                     p_student_number text default null, p_website text default null, p_minutes int default 30)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_project text := trim(coalesce(p_project, ''));
  v_hours   consultation_hours;
  v_place   bigint;
  v_token   uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  perform check_contact(p_name, p_email, p_link, p_student_number);
  if length(v_project) not between 3 and 300 then raise exception 'Say in a line what you need (3–300 characters).'; end if;
  if p_starts_at is null or p_starts_at < now() + interval '1 hour' then
    raise exception 'Please pick a time at least an hour from now.'; end if;
  if p_starts_at > now() + interval '120 days' then raise exception 'Please pick a time within the next 4 months.'; end if;
  if p_minutes is null or p_minutes not between 15 and 120 then raise exception 'Length must be 15–120 minutes.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'consultation' and a.status in ('requested', 'proposed') and p.email = v_email) >= 2 then
    raise exception 'You already have 2 open requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'consultation' and status in ('requested', 'proposed')) >= 20 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  -- owner and room: the first consultation hours entry (the lab's staff member), else the Tech Lab
  select h.* into v_hours from consultation_hours h order by h.id limit 1;
  v_place := coalesce(v_hours.place_id, (select id from places where iade_name like '%Tech Lab%' order by id limit 1));

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status, requester_id, owner_staff_id,
                          purpose, contact_link, status_token)
  values ('Consultation', 'booking', 'consultation', case when v_place is null then '{}' else array[v_place] end,
          p_starts_at, p_starts_at + make_interval(mins => p_minutes), 'requested',
          file_student(p_name, p_email, p_student_number), v_hours.staff_id,
          v_project, nullif(trim(coalesce(p_link, '')), ''), v_token);
  return v_token;
end $$;

drop function consultation_status(uuid);
create function consultation_status(p_token uuid)
returns table (status text, starts_at timestamptz, ends_at timestamptz, proposed_starts_at timestamptz, proposed_ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.status, a.starts_at, a.ends_at, a.proposed_starts_at, a.proposed_ends_at
  from activities a where a.status_token = p_token and a.kind = 'consultation'
$$;

-- The student answers a proposal on the private link. The token is the only authority.
create function answer_proposal(p_token uuid, p_accept boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
declare a activities;
begin
  select * into a from activities where status_token = p_token and kind = 'consultation' and status = 'proposed';
  if a.id is null then raise exception 'There is no proposal to answer.'; end if;
  if p_accept then
    update activities set starts_at = proposed_starts_at, ends_at = proposed_ends_at, status = 'approved',
           proposed_starts_at = null, proposed_ends_at = null where id = a.id;
  else
    update activities set status = 'rejected', proposed_starts_at = null, proposed_ends_at = null where id = a.id;
  end if;
end $$;

revoke all on function consultation_status(uuid), answer_proposal(uuid, boolean),
  request_consultation(text, text, text, text, timestamptz, text, text, int) from public;
grant execute on function consultation_status(uuid), answer_proposal(uuid, boolean),
  request_consultation(text, text, text, text, timestamptz, text, text, int) to anon, authenticated;
