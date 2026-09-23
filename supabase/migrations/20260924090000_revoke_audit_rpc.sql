-- Security advisor: audit() is a trigger function and needs no EXECUTE for triggers to fire; revoke it so it is not
-- exposed at /rest/v1/rpc/audit. is_staff() keeps EXECUTE for authenticated: the RLS policies call it as the user.
revoke execute on function audit() from authenticated;
