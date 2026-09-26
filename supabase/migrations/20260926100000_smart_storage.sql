-- Smart storage (docs/superpowers/specs/2026-09-26-smart-storage-design.md): place codes, individual assets, stocktake.
-- A place's code is printed on its QR label and is the node name in the Godot twin, so it stays fixed once labelled.

alter table places
  add column code text unique check (code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$'),
  add column counted_at timestamptz;   -- last stocktake; null = never counted, so its numbers are unconfirmed

update places set code = 'LAB' where name = 'Tech Lab';
update places set code = 'R15', name = 'Room 15 (gabinete)' where name = 'Fast storage';
update places set code = 'B2', name = '-2 floor storage' where name = 'Long-term storage';

alter table items
  add column note text,
  add column merged_into bigint references items (id);   -- set by merge_items(); the office hides merged items

create sequence asset_tag;
create table assets (
  id        bigint generated always as identity primary key,
  item_id   bigint not null references items (id),
  tag       text not null unique default 'TL-' || lpad(nextval('asset_tag')::text, 4, '0'),   -- or a legacy tag (GS-031, LV-01)
  serial    text unique,
  condition text not null default 'ok' check (condition in ('ok', 'broken', 'missing')),
  note      text,
  seen_at   timestamptz,               -- last ticked in a stocktake
  unique (id, item_id)
);
alter table assets enable row level security;
create policy staff_all on assets for all to authenticated using (is_staff()) with check (is_staff());
create trigger audit after insert or update or delete on assets for each row execute function audit();
revoke all on assets from anon;

-- An asset moves one at a time and only as its own item; merging items moves its movements along (on update cascade).
alter table movements
  add column asset_id bigint,
  add column note text,                -- provenance: 'import: …', 'stocktake'
  add constraint movement_asset foreign key (asset_id, item_id) references assets (id, item_id) on update cascade,
  add constraint movement_asset_one check (asset_id is null or abs(qty) = 1);

-- Where each asset is now: its latest movement. Issued = held by a person; consumed or adjusted away = nowhere.
create view asset_place with (security_invoker = true) as
select distinct on (asset_id) asset_id,
       case when kind in ('issue', 'consume') or (kind = 'adjust' and qty < 0) then null else to_place end as place_id,
       case when kind = 'issue' then person_id end as person_id,
       at
from movements
where asset_id is not null
order by asset_id, at desc, id desc;
revoke all on asset_place from anon;
