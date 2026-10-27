begin;
select plan(10);

select has_function('public','booking_unit_count',array['timestamptz','timestamptz','price_period'],'booking unit calculator exists');
select is(public.booking_unit_count('2026-01-01 10:00+00','2026-01-01 12:01+00','hour'),3,'partial hours round upward');
select is(public.booking_unit_count('2026-01-01 00:00+00','2026-01-04 00:00+00','day'),3,'whole days are exact');
select is(public.booking_unit_count('2026-01-01 00:00+00','2026-01-09 00:00+00','week'),2,'partial weeks round upward');
select is(public.booking_unit_count('2026-01-01 00:00+00','2026-01-31 00:00+00','month'),1,'monthly unit is deterministic');
select has_function('public','get_public_listing_booking_quote',array['uuid','timestamptz','timestamptz'],'public quote function exists');
select function_is_definer('public','get_public_listing_booking_quote',array['uuid','timestamptz','timestamptz'],'quote is derived server-side');
select has_function('public','create_instant_booking_checkout',array['uuid','text','text','text','timestamptz','timestamptz','integer','text','jsonb','bigint','text','boolean'],'atomic checkout exists');
select function_is_definer('public','create_instant_booking_checkout',array['uuid','text','text','text','timestamptz','timestamptz','integer','text','jsonb','bigint','text','boolean'],'checkout enforces server authority');
select is(has_function_privilege('anon','public.create_instant_booking_checkout(uuid,text,text,text,timestamptz,timestamptz,integer,text,jsonb,bigint,text,boolean)','EXECUTE'),false,'anonymous users cannot create instant checkout');

select * from finish();
rollback;
