-- Every TV page is a row the staff can reorder, edit or switch off, the automatic ones included:
-- 'events' plays the approved events of the next 14 days at its place, 'ideas' plays 3 random approved ideas (AI version).
alter table tv_slides drop constraint tv_slides_kind_check;
alter table tv_slides add constraint tv_slides_kind_check check (kind in ('media', 'bio', 'qr', 'text', 'events', 'ideas'));

insert into tv_slides (kind, title, url, position) values
  ('qr', 'Book time in the lab', 'https://berlogabob.github.io/openlabtwin/book/', 0),
  ('qr', 'Share a project idea', 'https://berlogabob.github.io/openlabtwin/ideas/', 1),
  ('events', 'Upcoming events', null, 2),
  ('ideas', 'Student ideas', null, 3);
