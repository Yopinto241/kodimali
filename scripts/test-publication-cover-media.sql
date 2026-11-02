\set ON_ERROR_STOP on
begin;
do $$ begin if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if; end $$;
create table public.listing_media(listing_id uuid,media_type text,is_cover boolean);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$ begin if value is distinct from true then raise exception 'FAIL: %',label; end if; end $$;
\ir ../supabase/migrations/20261102200000_publish_video_cover_with_image.sql
select pg_temp.ok(not listing_has_publishable_media('00000000-0000-4000-8000-000000000001'),'no media cannot publish');
insert into listing_media values('00000000-0000-4000-8000-000000000001','image',false);
select pg_temp.ok(not listing_has_publishable_media('00000000-0000-4000-8000-000000000001'),'image without selected cover cannot publish');
update listing_media set is_cover=true;
select pg_temp.ok(listing_has_publishable_media('00000000-0000-4000-8000-000000000001'),'image cover remains publishable');
update listing_media set is_cover=false;
insert into listing_media values('00000000-0000-4000-8000-000000000001','video',true);
select pg_temp.ok(listing_has_publishable_media('00000000-0000-4000-8000-000000000001'),'video cover with image gallery can publish');
delete from listing_media where media_type='image';
select pg_temp.ok(not listing_has_publishable_media('00000000-0000-4000-8000-000000000001'),'video alone still cannot bypass required image');
select 'PASS image covers, video covers with gallery image, missing cover/media and video-only rejection';
rollback;
