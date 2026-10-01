insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wall-upload', 'wall-upload', false, 2147483648, array['image/*', 'video/*'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy wall_upload_read on storage.objects for select to authenticated
  using (bucket_id = 'wall-upload' and public.is_staff());
create policy wall_upload_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'wall-upload' and public.is_staff());
create policy wall_upload_delete on storage.objects for delete to authenticated
  using (bucket_id = 'wall-upload' and public.is_staff());
