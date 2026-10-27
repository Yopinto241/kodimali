begin;
select plan(3);

select has_function('public','get_public_listing_booking_capabilities',array['uuid[]'],'batch public booking capability exists');
select function_is_definer('public','get_public_listing_booking_capabilities',array['uuid[]'],'batch capability is derived server-side');
select is(has_function_privilege('anon','public.get_public_listing_booking_capabilities(uuid[])','EXECUTE'),true,'public feeds may read safe booking labels');

select * from finish();
rollback;
