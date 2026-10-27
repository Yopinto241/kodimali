begin;
select plan(4);

select has_function('public','configure_owned_listing_booking',array['uuid','text','uuid','boolean','boolean','integer','jsonb','jsonb'],'verified owner booking configuration RPC exists');
select function_is_definer('public','configure_owned_listing_booking',array['uuid','text','uuid','boolean','boolean','integer','jsonb','jsonb'],'owner authority is checked server-side');
select is(has_function_privilege('anon','public.configure_owned_listing_booking(uuid,text,uuid,boolean,boolean,integer,jsonb,jsonb)','EXECUTE'),false,'anonymous users cannot configure listing booking');
select is(has_function_privilege('authenticated','public.configure_owned_listing_booking(uuid,text,uuid,boolean,boolean,integer,jsonb,jsonb)','EXECUTE'),true,'authenticated owners may invoke the server authority check');

select * from finish();
rollback;
