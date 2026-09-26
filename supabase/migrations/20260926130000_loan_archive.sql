-- The paper loan archive (docs/superpowers/specs/2026-09-26-equipment-and-archive-design.md): photos of the old A4 sheets
-- of what students took home, read by a vision model on Studio (scripts/archive_ocr.py on the edge node), checked by staff.
-- Historic loans live in archive_loans, apart from movements: they never change today's stock or who holds what.

create table archive_sheets (
  id          bigint generated always as identity primary key,
  sha256      text not null unique,                 -- the same photo is never read twice
  file_name   text not null,
  image_path  text,                                 -- the downscaled copy in the private storage bucket 'archive'
  photo_at    timestamptz,                          -- when the photo was taken (EXIF), not when the sheet was written
  raw_text    text,                                 -- the model's transcription
  extracted   jsonb,                                -- the model's fields: out_on, back_on, name, student_number, course, lines
  model       text,
  status      text not null default 'new' check (status in ('new', 'extracted', 'reviewed', 'rejected')),
  error       text,
  read_at     timestamptz,
  reviewed_by bigint references people (id),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);

create table archive_loans (
  id        bigint generated always as identity primary key,
  sheet_id  bigint not null references archive_sheets (id),
  person_id bigint references people (id),
  course    text,
  item_id   bigint references items (id),          -- null while the line matches no item
  item_text text not null,                          -- as written on the sheet
  qty       numeric not null default 1 check (qty > 0),
  out_on    date,
  back_on   date,
  check (back_on is null or out_on is null or back_on >= out_on)
);
create index archive_loans_item on archive_loans (item_id);

do $$ declare t text; begin
  foreach t in array array['archive_sheets', 'archive_loans'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
    execute format('create trigger audit after insert or update or delete on %I for each row execute function audit()', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- The sheet photos: a private bucket, staff only (the node uploads with the service key).
insert into storage.buckets (id, name, public) values ('archive', 'archive', false) on conflict (id) do nothing;
create policy archive_staff on storage.objects for all to authenticated
  using (bucket_id = 'archive' and public.is_staff()) with check (bucket_id = 'archive' and public.is_staff());

-- items.name_norm's rule, for text typed or read from a sheet.
create function norm_name(t text) returns text language sql immutable as $$
  select btrim(regexp_replace(translate(lower(t), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '[^a-z0-9]+', ' ', 'g'))
$$;

-- The closest items to a line from a sheet, best first (runs as the caller: staff only through RLS on items).
create function match_item(p_text text) returns table (id bigint, name text, score real)
language sql stable set search_path = public as $$
  select i.id, i.name, extensions.similarity(i.name_norm, norm_name(p_text))
  from items i
  where i.merged_into is null and extensions.similarity(i.name_norm, norm_name(p_text)) > 0.2
  order by 3 desc, i.name limit 5
$$;

-- Approve a reviewed sheet: its loans replaced by the staff member's lines in one step.
-- p_loans: [{"person_id": 3, "course": "…", "item_id": 12 | null, "item_text": "…", "qty": 1, "out_on": "2024-03-01", "back_on": null}]
create function approve_sheet(p_sheet bigint, p_loans jsonb) returns void
language plpgsql set search_path = public as $$
begin
  delete from archive_loans where sheet_id = p_sheet;
  insert into archive_loans (sheet_id, person_id, course, item_id, item_text, qty, out_on, back_on)
    select p_sheet, (l ->> 'person_id')::bigint, nullif(trim(l ->> 'course'), ''), (l ->> 'item_id')::bigint, trim(l ->> 'item_text'),
           coalesce((l ->> 'qty')::numeric, 1), (l ->> 'out_on')::date, (l ->> 'back_on')::date
    from jsonb_array_elements(p_loans) l;
  update archive_sheets set status = 'reviewed', reviewed_at = now(),
         reviewed_by = (select id from people where auth_user_id = auth.uid())
   where id = p_sheet;
end $$;
revoke all on function match_item(text), approve_sheet(bigint, jsonb) from public, anon;
grant execute on function match_item(text), approve_sheet(bigint, jsonb) to authenticated;

-- Merging items also moves their historic loans.
create or replace function merge_items(p_survivor bigint, p_losers bigint[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then
    raise exception 'Only lab staff can merge items.';
  end if;
  if p_survivor = any (p_losers) then
    raise exception 'An item cannot be merged into itself.';
  end if;
  if exists (select 1 from items where id = p_survivor and merged_into is not null) then
    raise exception 'That item was already merged into another one.';
  end if;
  update assets set item_id = p_survivor where item_id = any (p_losers);   -- their movements follow (on update cascade)
  update movements set item_id = p_survivor where item_id = any (p_losers);
  update archive_loans set item_id = p_survivor where item_id = any (p_losers);
  -- a booking that listed both: one kit line with both quantities
  insert into activity_items (activity_id, item_id, qty, prepared)
    select activity_id, p_survivor, sum(qty), bool_and(prepared) from activity_items where item_id = any (p_losers) group by activity_id
    on conflict (activity_id, item_id) do update set qty = activity_items.qty + excluded.qty;
  delete from activity_items where item_id = any (p_losers);
  update items set merged_into = p_survivor where id = any (p_losers);
end $$;

-- ---------- usage statistics (thesis): the archive and today's loans in one shape ----------

-- One row per loan: 'archive' from the paper sheets, 'live' from issue movements.
create view usage_events with (security_invoker = true) as
  select 'archive' as source, l.item_id, l.person_id, l.course, l.qty, l.out_on as day, l.back_on as back_on
  from archive_loans l where l.item_id is not null
  union all
  select 'live', m.item_id, m.person_id, null, m.qty, (m.at at time zone 'Europe/Lisbon')::date, null
  from movements m where m.kind = 'issue';

create view usage_by_item with (security_invoker = true) as
  select e.item_id, i.name, date_trunc('month', e.day)::date as month, e.source, count(*) as loans, sum(e.qty) as units,
         count(distinct e.person_id) as people
  from usage_events e join items i on i.id = e.item_id
  where e.day is not null
  group by e.item_id, i.name, date_trunc('month', e.day), e.source;

create view usage_by_course with (security_invoker = true) as
  select e.course, e.item_id, i.name, count(*) as loans, sum(e.qty) as units
  from usage_events e join items i on i.id = e.item_id
  where e.course is not null
  group by e.course, e.item_id, i.name;

-- The most units out at once, against what the lab owns now (on the shelves plus on loan). Archive loans count only with both
-- dates; live loans run from issue to return. peak >= owned: the item ran out, a candidate to buy more of.
create view peak_on_loan with (security_invoker = true) as
  with ev as (
    select item_id, out_on as d, qty as delta from archive_loans where item_id is not null and out_on is not null and back_on is not null
    union all
    select item_id, back_on + 1, -qty from archive_loans where item_id is not null and out_on is not null and back_on is not null
    union all
    select item_id, (at at time zone 'Europe/Lisbon')::date, case kind when 'issue' then qty else -qty end
    from movements where kind in ('issue', 'return') and person_id is not null
  ), running as (
    select item_id, d, sum(sum(delta)) over (partition by item_id order by d) as out_now from ev group by item_id, d
  )
  select r.item_id, i.name, max(r.out_now) as peak,
         coalesce((select sum(s.qty) from stock s where s.item_id = r.item_id), 0)
           + coalesce((select sum(o.qty) from on_loan o where o.item_id = r.item_id), 0) as owned
  from running r join items i on i.id = r.item_id
  group by r.item_id, i.name;

revoke all on usage_events, usage_by_item, usage_by_course, peak_on_loan from anon;
