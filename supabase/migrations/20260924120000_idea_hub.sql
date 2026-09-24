-- Idea hub (docs/superpowers/specs/2026-09-24-idea-hub-design.md). Also moves the contact checks and the "file this
-- student by email" step into two helpers shared by request_consultation() and submit_idea().

create extension if not exists vector with schema extensions;

create table ideas (
  id               bigint generated always as identity primary key,
  person_id        bigint not null references people (id),
  body             text not null,
  link             text,
  can_bring        text,
  looking_for      text,
  status           text not null default 'new' check (status in ('new', 'approved', 'archived')),
  workshop         boolean not null default false,
  status_token     uuid not null unique default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  ai_title         text,
  ai_summary       text,
  ai_keywords      text[] not null default '{}',
  ai_model         text,
  ai_done_at       timestamptz,
  embedding        extensions.vector(768)    -- of ai_summary, for "similar" matches
);

-- The AI's English skill phrases, one row each, so "complementary" compares phrase with phrase
-- (whole lists blur: "electronics, soil sensors" vs "electronics, esp32" scored only 0.55).
create table idea_skills (
  idea_id    bigint not null references ideas (id) on delete cascade,
  side       text not null check (side in ('brings', 'needs')),
  phrase     text not null,
  embedding  extensions.vector(768) not null,
  primary key (idea_id, side, phrase)
);
alter table idea_skills enable row level security;
create policy staff_all on idea_skills for all to authenticated using (is_staff()) with check (is_staff());
revoke all on idea_skills from anon;   -- not audited: derived by the AI job, rebuilt on every reprocess

create table idea_matches (
  idea_a     bigint not null references ideas (id) on delete cascade,
  idea_b     bigint not null references ideas (id) on delete cascade,
  kind       text not null check (kind in ('similar', 'complementary')),
  score      real not null,
  reason     text not null default '',
  a_connect  boolean not null default false,
  b_connect  boolean not null default false,
  primary key (idea_a, idea_b, kind),
  check (idea_a < idea_b)
);

do $$ declare t text; begin
  foreach t in array array['ideas', 'idea_matches'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy staff_all on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
    execute format('create trigger audit after insert or update or delete on %I for each row execute function audit()', t);
    execute format('revoke all on %I from anon', t);
  end loop;
end $$;

-- Shared by the public forms: the same contact rules everywhere.
create function check_contact(p_name text, p_email text, p_link text, p_number text) returns void
language plpgsql immutable as $$
begin
  if length(trim(coalesce(p_name, ''))) not between 2 and 100 then raise exception 'Please give your name (2–100 characters).'; end if;
  if length(trim(coalesce(p_email, ''))) not between 3 and 200 or lower(trim(p_email)) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please give a valid email.'; end if;
  if nullif(trim(coalesce(p_link, '')), '') is not null and (length(trim(p_link)) > 500 or trim(p_link) !~* '^https?://\S+$') then
    raise exception 'The link must start with http:// or https://.'; end if;
  if nullif(trim(coalesce(p_number, '')), '') is not null and trim(p_number) !~ '^[A-Za-z0-9-]{1,30}$' then
    raise exception 'The student number can only have letters, digits and dashes.'; end if;
end $$;

-- One people row per email: the student's lab history. Staff names are never overwritten.
create function file_student(p_name text, p_email text, p_number text) returns bigint
language sql volatile set search_path = public as $$
  insert into people (name, kind, email, student_number)
  values (trim(p_name), 'student', lower(trim(p_email)), nullif(trim(coalesce(p_number, '')), ''))
  on conflict (email) do update
    set name = case when people.kind = 'student' then excluded.name else people.name end,
        student_number = coalesce(excluded.student_number, people.student_number)
  returning id
$$;

create or replace function request_consultation(p_name text, p_email text, p_project text, p_link text, p_starts_at timestamptz,
                                                p_student_number text default null, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_project text := trim(coalesce(p_project, ''));
  v_local   timestamp := p_starts_at at time zone 'Europe/Lisbon';
  v_hours   consultation_hours;
  v_token   uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot: bots get a token, nothing is stored
  perform check_contact(p_name, p_email, p_link, p_student_number);
  if length(v_project) not between 10 and 2000 then raise exception 'Describe your project in 10–2000 characters.'; end if;
  if not exists (select 1 from free_slots(v_local::date, v_local::date) f where f.starts_at = p_starts_at) then
    raise exception 'That time is no longer free. Please pick another.'; end if;
  if (select count(*) from activities a join people p on p.id = a.requester_id
      where a.kind = 'consultation' and a.status = 'requested' and p.email = v_email) >= 2 then
    raise exception 'You already have 2 open requests. Please wait for an answer.'; end if;
  if (select count(*) from activities where kind = 'consultation' and status = 'requested') >= 20 then
    raise exception 'Too many open requests right now. Please try again in a few days.'; end if;

  select h.* into v_hours from consultation_hours h
   where h.weekday = extract(isodow from v_local)
     and v_local::time >= h.from_time and v_local::time + make_interval(mins => h.slot_minutes) <= h.to_time
   order by h.id limit 1;

  insert into activities (title, layer, kind, place_ids, starts_at, ends_at, status, requester_id, owner_staff_id,
                          purpose, contact_link, status_token)
  values ('Consultation', 'booking', 'consultation', array[v_hours.place_id], p_starts_at,
          p_starts_at + make_interval(mins => v_hours.slot_minutes), 'requested',
          file_student(p_name, p_email, p_student_number), v_hours.staff_id,
          v_project, nullif(trim(coalesce(p_link, '')), ''), v_token);
  return v_token;
end $$;

-- A student's idea. Returns the private status token.
create function submit_idea(p_name text, p_email text, p_body text, p_link text, p_can_bring text, p_looking_for text,
                            p_student_number text default null, p_website text default null)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare
  v_body  text := trim(coalesce(p_body, ''));
  v_token uuid := gen_random_uuid();
begin
  if coalesce(p_website, '') <> '' then return v_token; end if;  -- honeypot
  perform check_contact(p_name, p_email, p_link, p_student_number);
  if length(v_body) not between 10 and 4000 then raise exception 'Describe your idea in 10–4000 characters.'; end if;
  if length(coalesce(p_can_bring, '')) > 500 or length(coalesce(p_looking_for, '')) > 500 then
    raise exception '"I can bring" and "I''m looking for" are at most 500 characters each.'; end if;
  if (select count(*) from ideas i join people p on p.id = i.person_id
      where p.email = lower(trim(p_email)) and i.created_at > now() - interval '24 hours') >= 5 then
    raise exception 'That is 5 ideas today already. Please send more tomorrow.'; end if;
  insert into ideas (person_id, body, link, can_bring, looking_for, status_token)
  values (file_student(p_name, p_email, p_student_number), v_body, nullif(trim(coalesce(p_link, '')), ''),
          nullif(trim(coalesce(p_can_bring, '')), ''), nullif(trim(coalesce(p_looking_for, '')), ''), v_token);
  return v_token;
end $$;

-- What the private link shows: the student's own idea, and matches only between approved ideas.
-- Contact details appear only when both students tapped "I'd like to connect".
create function idea_status(p_token uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'idea', json_build_object('body', i.body, 'link', i.link, 'can_bring', i.can_bring, 'looking_for', i.looking_for,
                              'status', i.status, 'processed', i.ai_done_at is not null, 'title', i.ai_title,
                              'summary', i.ai_summary, 'keywords', i.ai_keywords),
    'matches', case when i.status <> 'approved' then '[]'::json else coalesce((
      select json_agg(json_build_object(
               'other', o.id, 'kind', m.kind, 'reason', m.reason, 'title', o.ai_title,
               'first_name', split_part(trim(op.name), ' ', 1),
               'i_connected', case when m.idea_a = i.id then m.a_connect else m.b_connect end,
               'they_connected', case when m.idea_a = i.id then m.b_connect else m.a_connect end,
               'contact', case when m.a_connect and m.b_connect then json_build_object('email', op.email, 'link', o.link) end)
             order by m.score desc)
      from idea_matches m
      join ideas o on o.id = case when m.idea_a = i.id then m.idea_b else m.idea_a end
      join people op on op.id = o.person_id
      where (m.idea_a = i.id or m.idea_b = i.id) and o.status = 'approved'), '[]'::json) end)
  from ideas i where i.status_token = p_token
$$;

-- "I'd like to connect": sets the caller's side of every match between the two approved ideas.
create function idea_connect(p_token uuid, p_other bigint) returns void
language plpgsql volatile security definer set search_path = public as $$
declare v_me ideas;
begin
  select * into v_me from ideas where status_token = p_token;
  if v_me.id is null or v_me.status <> 'approved' then raise exception 'This idea is not approved yet.'; end if;
  if not exists (select 1 from ideas where id = p_other and status = 'approved') then raise exception 'That idea is not available.'; end if;
  update idea_matches
     set a_connect = a_connect or idea_a = v_me.id,
         b_connect = b_connect or idea_b = v_me.id
   where (idea_a = v_me.id and idea_b = p_other) or (idea_b = v_me.id and idea_a = p_other);
  if not found then raise exception 'These ideas are not matched.'; end if;
end $$;

revoke all on function check_contact(text, text, text, text), file_student(text, text, text) from public, anon, authenticated;
revoke all on function submit_idea(text, text, text, text, text, text, text, text), idea_status(uuid), idea_connect(uuid, bigint) from public;
grant execute on function submit_idea(text, text, text, text, text, text, text, text), idea_status(uuid), idea_connect(uuid, bigint)
  to anon, authenticated;
