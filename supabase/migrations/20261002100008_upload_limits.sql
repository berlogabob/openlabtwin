-- The office web app reads a whole file into browser memory before upload (file_picker on the web gives bytes only),
-- so 2 GB could exhaust a laptop's tab: cap at 500 MB. Delete only your own uploads, as planned.
update storage.buckets set file_size_limit = 524288000 where id = 'wall-upload';
drop policy wall_upload_delete on storage.objects;
create policy wall_upload_delete on storage.objects for delete to authenticated
  using (bucket_id = 'wall-upload' and public.is_staff() and owner_id = (select auth.uid())::text);
