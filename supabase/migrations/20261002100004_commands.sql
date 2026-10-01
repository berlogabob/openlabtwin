-- One-shot request consumed by the wall server, then sent to a screen client.
alter table wall_state add column command jsonb
  check (command is null or (coalesce(command ->> 'kind' in ('restart', 'reboot'), false) and command ? 'code' and command ? 'at'));
