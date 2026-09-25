-- The edge node's heartbeat for the TV: when the playlist was last built, what it holds, and the last error.
-- One row (id 1). Written by the node (service role) every minute; staff read it in the office.
create table tv_status (
  id       int primary key default 1 check (id = 1),
  built_at timestamptz,
  pages    int not null default 0,
  media    int not null default 0,
  takeover boolean not null default false,
  error    text,
  error_at timestamptz
);
alter table tv_status enable row level security;
create policy staff_read on tv_status for select to authenticated using (is_staff());
revoke all on tv_status from anon;
revoke insert, update, delete, truncate on tv_status from authenticated;
