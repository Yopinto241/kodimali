begin;
select plan(3);
select has_function('public','confirm_customer_fulfillment_milestone',array['uuid'],'customer fulfillment confirmation exists');
select function_is_definer('public','confirm_customer_fulfillment_milestone',array['uuid'],'customer confirmation authorization is server-side');
select is(has_function_privilege('anon','public.confirm_customer_fulfillment_milestone(uuid)','EXECUTE'),false,'anonymous users cannot confirm fulfillment');
select * from finish();
rollback;
