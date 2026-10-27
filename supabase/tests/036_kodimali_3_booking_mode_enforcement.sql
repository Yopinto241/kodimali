begin;
select plan(8);

select has_function('public','apply_listing_booking_mode',array[]::text[],'booking mode normalization trigger exists');
select has_trigger('public','booking_requests','a_apply_listing_booking_mode','booking requests apply listing mode before legacy triggers');
select function_is_definer('public','create_instant_booking_hold',array[]::text[],'instant hold remains server-authoritative');
select has_function('public','get_public_listing_booking_capability',array['uuid'],'public booking capability function exists');
select function_is_definer('public','get_public_listing_booking_capability',array['uuid'],'public capability is derived server-side');
select is(has_function_privilege('anon','public.get_public_listing_booking_capability(uuid)','EXECUTE'),true,'visitors may read non-sensitive booking capability');
select is(has_function_privilege('anon','public.apply_listing_booking_mode()','EXECUTE'),false,'trigger function is not directly callable by visitors');
select is(public.kodimali_feature_enabled('instant_booking'),false,'Instant Booking remains globally disabled by default');

select * from finish();
rollback;
