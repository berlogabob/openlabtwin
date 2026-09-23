-- Who holds what right now: issued minus returned, per item and person. Like stock, never stored.
create view on_loan with (security_invoker = true) as
  select item_id, person_id, sum(case kind when 'issue' then qty else -qty end) as qty
  from movements
  where kind in ('issue', 'return') and person_id is not null
  group by item_id, person_id
  having sum(case kind when 'issue' then qty else -qty end) <> 0;

revoke all on on_loan from anon;
