-- Prevent duplicate TyLog steps and issuing a tagged unit that is already out.
create unique index movements_tylog_note on movements (note) where note like 'tylog:%';

create function prevent_asset_double_issue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  asset_tag text;
  latest_kind text;
  latest_person_id bigint;
  holder_name text;
  issued_at timestamptz;
begin
  if new.kind <> 'issue' or new.asset_id is null then
    return new;
  end if;

  select tag into asset_tag from assets where id = new.asset_id for update;
  select kind, person_id, at into latest_kind, latest_person_id, issued_at
  from movements where asset_id = new.asset_id order by at desc, id desc limit 1;

  if latest_kind = 'issue' then
    select name into holder_name from people where id = latest_person_id;
    raise exception '% is already out with % since %', asset_tag, holder_name, to_char(issued_at, 'YYYY-MM-DD')
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger prevent_asset_double_issue
before insert on movements for each row execute function prevent_asset_double_issue();

comment on index movements_tylog_note is 'A TyLog task step may be recorded only once.';
comment on function prevent_asset_double_issue() is 'A tagged unit already issued must be returned before it can be issued again.';
