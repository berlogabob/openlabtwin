-- The student number is the lab's local ID for a person (user, 2026-09-27): every public form asks for it, and the database
-- refuses a request without it. Staff and professors give their staff number. check_contact() is shared by Book me,
-- the idea hub and equipment requests, so all three follow.
-- Equipment requests also take several courses now (picked from the timetable, joined with '; '): up to 300 characters.

create or replace function check_contact(p_name text, p_email text, p_link text, p_number text) returns void
language plpgsql immutable as $$
begin
  if length(trim(coalesce(p_name, ''))) not between 2 and 100 then raise exception 'Please give your name (2–100 characters).'; end if;
  if length(trim(coalesce(p_email, ''))) not between 3 and 200 or lower(trim(p_email)) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please give a valid email.'; end if;
  if nullif(trim(coalesce(p_link, '')), '') is not null and (length(trim(p_link)) > 500 or trim(p_link) !~* '^https?://\S+$') then
    raise exception 'The link must start with http:// or https://.'; end if;
  if nullif(trim(coalesce(p_number, '')), '') is null then
    raise exception 'Please give your student number (staff: your staff number).'; end if;
  if trim(p_number) !~ '^[A-Za-z0-9-]{1,30}$' then
    raise exception 'The student number can only have letters, digits and dashes.'; end if;
end $$;
revoke all on function check_contact(text, text, text, text) from public, anon, authenticated;

create or replace function request_equipment(p_name text, p_email text, p_student_number text, p_use text, p_course text,
                                  p_starts_at timestamptz, p_ends_at timestamptz, p_repeat_until date, p_items jsonb,
                                  p_other text, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email  text := lower(trim(coalesce(p_email, '')));
  v_other  text := trim(coalesce(p_other, ''));
  v_course text := trim(coalesce(p_course, ''));
  v_items  jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]' end;
  v_day    date := (p_starts_at at time zone 'Europe/Lisbon')::date;
  v_token  uuid := gen_random_uuid();
  v_id     bigint;
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  perform check_contact(p_name, p_email, null, p_student_number);
  if coalesce(p_use, '') not in ('class', 'lab', 'home') then
    raise exception 'Say what it is for: a class, lab work or taking it home.'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then raise exception 'The end must be after the start.'; end if;
  if p_starts_at < now() - interval '1 hour' or p_starts_at > now() + interval '180 days' then
    raise exception 'Pick a date from today up to 6 months ahead.'; end if;
  if p_ends_at > p_starts_at + interval '90 days' then raise exception 'Ask for at most 90 days at a time.'; end if;
  if p_repeat_until is not null and (p_use <> 'class' or p_repeat_until < v_day or p_repeat_until > v_day + 180) then
    raise exception 'Weekly repeats are for classes, up to 6 months.'; end if;
  if jsonb_array_length(v_items) > 20 then raise exception 'At most 20 different items per request.'; end if;
  if jsonb_array_length(v_items) = 0 and length(v_other) < 3 then raise exception 'Pick at least one item, or say what you need.'; end if;
  if length(v_other) > 500 or length(v_course) > 300 then
    raise exception 'Keep "something else" under 500 characters and the courses under 300.'; end if;
  if exists (select 1 from jsonb_array_elements(v_items) e
             where case when jsonb_typeof(e -> 'item_id') = 'number' and jsonb_typeof(e -> 'qty') = 'number'
                        then (e ->> 'qty')::numeric not between 1 and 100
                             or not exists (select 1 from items i where i.id = (e ->> 'item_id')::bigint and i.lendable and i.merged_into is null)
                        else true end) then
    raise exception 'One of the items is not on the list, or its quantity is not 1–100.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'equipment' and a.status = 'requested' and a.status_token is not null and p.email = v_email) >= 3 then
    raise exception 'You already have 3 open equipment requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'equipment' and status = 'requested' and status_token is not null) >= 30 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, rrule, status, requester_id, purpose, status_token)
  values (case p_use when 'class' then 'Class kit' when 'lab' then 'Lab work' else 'Take-home kit' end,
          'booking', 'equipment',
          case when p_use = 'lab' then coalesce((select array[id] from places where code = 'LAB'), '{}') else '{}' end,
          p_starts_at, p_ends_at,
          case when p_repeat_until is not null then 'FREQ=WEEKLY;UNTIL=' || to_char(p_repeat_until, 'YYYYMMDD') || 'T235959' end,
          'requested', file_student(p_name, p_email, p_student_number),
          concat_ws(E'\n', case p_use when 'class' then 'For a class' when 'lab' then 'Lab work' else 'To take home' end
                              || coalesce(': ' || nullif(v_course, ''), ''),
                    nullif(v_other, '')),
          v_token)
  returning id into v_id;
  insert into activity_items (activity_id, item_id, qty)
    select v_id, (e ->> 'item_id')::bigint, sum((e ->> 'qty')::numeric) from jsonb_array_elements(v_items) e group by 1, 2;
  return v_token;
end $$;
revoke all on function request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) from public;
grant execute on function request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) to anon, authenticated;
