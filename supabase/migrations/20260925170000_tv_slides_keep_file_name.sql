-- A page keeps its file name even while the file is missing (renamed, being copied, a share hiccup): the node skips
-- such pages and plays them again once the file is back. The foreign key used to blank the name for good.
alter table tv_slides drop constraint tv_slides_media_name_fkey;
