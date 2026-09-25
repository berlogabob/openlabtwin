-- seconds null = play the video to its end (the default for videos); a number cuts it after that many seconds.
alter table tv_slides alter column seconds drop not null;
update tv_slides set seconds = null
 where kind = 'media' and media_name in (select name from tv_media where kind = 'video');
