-- Book me: only the student number is required (user, 2026-10-07). No name: the number stands in. No email: number@iade.pt.
-- No line about what is needed: optional. The other public forms keep their rules.

create or replace function request_consultation(p_name text, p_email text, p_project text, p_link text, p_starts_at timestamptz,
                                     p_student_number text default null, p_website text default null, p_minutes int default 30)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_number  text := trim(coalesce(p_student_number, ''));
  v_name    text := coalesce(nullif(trim(coalesce(p_name, '')), ''), v_number);
  v_email   text := lower(coalesce(nullif(trim(coalesce(p_email, '')), ''), v_number || '@iade.pt'));
  v_project text := trim(coalesce(p_project, ''));
  v_hours   consultation_hours;
  v_place   bigint;
  v_token   uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  if v_number = '' then raise exception 'Please give your student number (staff: your staff number).'; end if;
  perform check_contact(v_name, v_email, p_link, v_number);
  if v_project <> '' and length(v_project) not between 3 and 300 then raise exception 'Keep it to a line (3–300 characters), or leave it empty.'; end if;
  if p_starts_at is null or p_starts_at < now() + interval '1 hour' then
    raise exception 'Please pick a time at least an hour from now.'; end if;
  if p_starts_at > now() + interval '120 days' then raise exception 'Please pick a time within the next 4 months.'; end if;
  if p_minutes is null or p_minutes not between 15 and 120 then raise exception 'Length must be 15–120 minutes.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'consultation' and a.status in ('requested', 'proposed') and p.email = v_email) >= 2 then
    raise exception 'You already have 2 open requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'consultation' and status in ('requested', 'proposed')) >= 20 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  select h.* into v_hours from consultation_hours h order by h.id limit 1;
  v_place := coalesce(v_hours.place_id, (select id from places where iade_name like '%Tech Lab%' order by id limit 1));

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status, requester_id, owner_staff_id,
                          purpose, contact_link, status_token)
  values ('Consultation', 'booking', 'consultation', case when v_place is null then '{}' else array[v_place] end,
          p_starts_at, p_starts_at + make_interval(mins => p_minutes), 'requested',
          file_student(v_name, v_email, v_number), v_hours.staff_id,
          nullif(v_project, ''), nullif(trim(coalesce(p_link, '')), ''), v_token);
  return v_token;
end $$;
