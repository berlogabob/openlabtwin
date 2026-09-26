-- Equipment requests (docs/superpowers/specs/2026-09-26-equipment-and-archive-design.md): anyone with an email can ask for
-- equipment for a class, lab work or to take home. It lands as a requested 'equipment' booking with its kit filled in;
-- staff approve, prepare and issue it as any other kit. Asking is optional everywhere: no booking needs a kit.

-- Which items the public list offers. Portable ones by default; staff untick what isn't lent.
alter table items add column lendable boolean not null default false;
update items set lendable = true where kind = 'portable' and merged_into is null;

-- The public catalogue: names only. Places, counts and tags never leave the database this way.
create function equipment_catalogue() returns table (id bigint, name text, kind text)
language sql stable security definer set search_path = public as $$
  select id, name, kind from items where lendable and merged_into is null order by name
$$;

-- p_use: class | lab | home. p_items: [{"item_id": 12, "qty": 3}, ...]. p_repeat_until: weekly, classes only.
create function request_equipment(p_name text, p_email text, p_student_number text, p_use text, p_course text,
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
  if length(v_other) > 500 or length(v_course) > 100 then
    raise exception 'Keep "something else" under 500 characters and the course under 100.'; end if;
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

-- What the private link shows: status, dates, the items asked for (names only).
create function equipment_status(p_token uuid)
returns table (status text, starts_at timestamptz, ends_at timestamptz, rrule text, items jsonb)
language sql stable security definer set search_path = public as $$
  select a.status, a.starts_at, a.ends_at, a.rrule,
         coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'qty', k.qty) order by i.name)
                   from activity_items k join items i on i.id = k.item_id where k.activity_id = a.id), '[]')
  from activities a where a.status_token = p_token and a.kind = 'equipment'
$$;

revoke all on function equipment_catalogue(), equipment_status(uuid),
  request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) from public;
grant execute on function equipment_catalogue(), equipment_status(uuid),
  request_equipment(text, text, text, text, text, timestamptz, timestamptz, date, jsonb, text, text) to anon, authenticated;

-- Needs attention gains kits that weren't brought back.
create or replace view storage_issues with (security_invoker = true) as
select * from (
  select 'negative_stock' as code, s.item_id as a_id, s.place_id as b_id,
         i.name || ': ' || s.qty || ' at ' || p.name as detail, 'neg:' || s.item_id || ':' || s.place_id as key
  from stock s join items i on i.id = s.item_id join places p on p.id = s.place_id
  where s.qty < 0
  union all
  select 'never_counted', p.id, null, p.name || ' has never been counted', 'count:' || p.id
  from places p
  where p.counted_at is null and exists (select 1 from stock s where s.place_id = p.id and s.qty <> 0)
  union all
  select 'stale_count', p.id, null, p.name || ' last counted ' || to_char(p.counted_at, 'YYYY-MM-DD'),
         'stale:' || p.id || ':' || to_char(p.counted_at, 'YYYYMMDD')
  from places p
  where p.counted_at < now() - interval '180 days'
  union all
  select 'possible_duplicate', a.id, b.id, a.name || ' / ' || b.name, 'dup:' || a.id || ':' || b.id
  from items a join items b on a.id < b.id
  where a.merged_into is null and b.merged_into is null and extensions.similarity(a.name_norm, b.name_norm) > 0.5
  union all
  select 'asset_' || x.condition, x.id, x.item_id, i.name || ' ' || x.tag || ' is ' || x.condition, 'asset:' || x.id || ':' || x.condition
  from assets x join items i on i.id = x.item_id
  where x.condition <> 'ok'
  union all
  -- a booking's kit still out a day after the booking ended (a repeating one: a day after the session of its last issue)
  select 'kit_not_returned', k.activity_id, null,
         a.title || ' (' || to_char(a.starts_at at time zone 'Europe/Lisbon', 'YYYY-MM-DD') || '): ' || k.n_out || ' not returned',
         'kit:' || k.activity_id
  from (select activity_id, sum(case kind when 'issue' then qty else -qty end) as n_out,
               max(at) filter (where kind = 'issue') as last_issue
        from movements where activity_id is not null and kind in ('issue', 'return') group by activity_id) k
  join activities a on a.id = k.activity_id
  where k.n_out > 0
    and case when a.rrule is null then a.ends_at else k.last_issue + (a.ends_at - a.starts_at) end < now() - interval '1 day'
) issue
where key not in (select key from issue_waivers);
