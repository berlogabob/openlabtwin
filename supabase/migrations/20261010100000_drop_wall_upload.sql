-- Wall media stays on the node; the office no longer uploads. Policies go here; empty and delete the
-- wall-upload bucket in the Storage dashboard (SQL cannot delete storage objects).
drop policy if exists wall_upload_read on storage.objects;
drop policy if exists wall_upload_insert on storage.objects;
drop policy if exists wall_upload_delete on storage.objects;
