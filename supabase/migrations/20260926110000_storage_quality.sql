-- Needs attention for storage, the UNIDCOM RIMS way (output_quality.sql, output_merge.sql): every rule in one view,
-- waivers for false alarms, and a soft merge for duplicates.
create extension if not exists pg_trgm with schema extensions;

-- ponytail: translate() instead of unaccent, which isn't immutable and so can't feed a generated column.
alter table items add column name_norm text generated always as (
  btrim(regexp_replace(translate(lower(name), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc'), '[^a-z0-9]+', ' ', 'g'))
) stored;
create index items_name_norm_trgm on items using gin (name_norm extensions.gin_trgm_ops);

create table issue_waivers (
  key      text primary key,           -- storage_issues.key, e.g. 'dup:12:34'
  reason   text,
  by_staff bigint references people (id),
  at       timestamptz not null default now()
);
alter table issue_waivers enable row level security;
create policy staff_all on issue_waivers for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on issue_waivers for each row execute function audit();
revoke all on issue_waivers from anon;

-- a_id / b_id: negative_stock item/place, place issues the place, duplicates both items, asset issues asset/item.
-- The stale key carries the count date, so a waiver lapses with the next count.
-- ponytail: duplicate check is an items × items self-join; fine for hundreds of items, use the % operator past that.
create view storage_issues with (security_invoker = true) as
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
) issue
where key not in (select key from issue_waivers);
revoke all on storage_issues from anon;

-- Soft merge: the duplicates' assets, movements and kit lines go to the survivor; the duplicates stay, marked merged_into.
create function merge_items(p_survivor bigint, p_losers bigint[]) returns void
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
  -- a booking that listed both: one kit line with both quantities
  insert into activity_items (activity_id, item_id, qty, prepared)
    select activity_id, p_survivor, sum(qty), bool_and(prepared) from activity_items where item_id = any (p_losers) group by activity_id
    on conflict (activity_id, item_id) do update set qty = activity_items.qty + excluded.qty;
  delete from activity_items where item_id = any (p_losers);
  update items set merged_into = p_survivor where id = any (p_losers);
end $$;
revoke all on function merge_items(bigint, bigint[]) from public, anon;
grant execute on function merge_items(bigint, bigint[]) to authenticated;
