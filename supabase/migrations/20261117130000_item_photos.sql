alter table assets drop constraint assets_condition_check;
alter table assets add constraint assets_condition_check check (condition in ('ok', 'broken', 'missing', 'disassembled'));

create table item_photos (
  id bigint generated always as identity primary key,
  item_id bigint not null references items (id),
  asset_id bigint,
  foreign key (asset_id, item_id) references assets (id, item_id) on update cascade,
  path text not null unique,
  state text not null default 'reference' check (state in ('reference', 'ok', 'broken', 'disassembled', 'missing')),
  note text,
  taken_at timestamptz not null default now(),
  taken_by uuid default auth.uid()
);
create index item_photos_item on item_photos (item_id);
alter table item_photos enable row level security;
create policy staff_all on item_photos for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on item_photos for each row execute function audit();
revoke all on item_photos from anon;

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
  update item_photos set item_id = p_survivor where item_id = any (p_losers);
  update archive_loans set item_id = p_survivor where item_id = any (p_losers);
  -- a booking that listed both: one kit line with both quantities
  insert into activity_items (activity_id, item_id, qty, prepared)
    select activity_id, p_survivor, sum(qty), bool_and(prepared) from activity_items where item_id = any (p_losers) group by activity_id
    on conflict (activity_id, item_id) do update set qty = activity_items.qty + excluded.qty;
  delete from activity_items where item_id = any (p_losers);
  update items set merged_into = p_survivor where id = any (p_losers);
end $$;


insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('item-photos', 'item-photos', false, 10485760, array['image/*'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create policy item_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'item-photos' and public.is_staff());
create policy item_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'item-photos' and public.is_staff());
create policy item_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'item-photos' and public.is_staff());
