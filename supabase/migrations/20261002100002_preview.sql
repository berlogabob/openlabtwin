insert into storage.buckets (id, name, public) values ('wall-preview', 'wall-preview', false)
on conflict (id) do nothing;

create policy wall_preview_staff on storage.objects for select to authenticated
  using (bucket_id = 'wall-preview' and public.is_staff());

alter table wall_status add column preview_at timestamptz;
