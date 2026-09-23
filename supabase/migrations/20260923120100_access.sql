-- Who may touch what. Three layers, as in UNIDCOM RIMS: grants (tables), RLS (rows), export allowlist (fields).

create table audit_log (
  id         bigint generated always as identity primary key,
  table_name text not null,
  row_id     bigint,
  op         text not null,
  old_row    jsonb,
  new_row    jsonb,
  actor      uuid default auth.uid(),
  at         timestamptz not null default now()
);

create function audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (table_name, row_id, op, old_row, new_row)
  values (tg_table_name,
          coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id')::bigint,
          tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;

-- ponytail: lessons are not audited; the scraper rewrites thousands every 6 h. Git history of all.json covers them.
do $$ declare t text; begin
  foreach t in array array['places', 'items', 'people', 'organizations', 'activities', 'activity_items', 'movements'] loop
    execute format('create trigger audit after insert or update or delete on %I for each row execute function audit()', t);
  end loop;
end $$;

create function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from people where auth_user_id = auth.uid() and is_staff)
$$;

do $$ declare t text; begin
  foreach t in array array['places', 'items', 'people', 'organizations', 'activities', 'activity_items', 'movements', 'lessons'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;
alter table audit_log enable row level security;
create policy staff_read on audit_log for select to authenticated using (is_staff());

-- Grants: anon gets nothing, now and for future tables.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon, public;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon, public;
grant execute on function is_staff() to authenticated;

-- Staff write rules the policies can't express.
revoke update, delete, truncate on movements from authenticated;         -- append-only; corrections are 'adjust' rows
revoke insert, update, delete, truncate on audit_log from authenticated;
revoke insert, update, delete, truncate on lessons from authenticated;   -- only the scraper (service_role) writes lessons
