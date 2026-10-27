begin;
select plan(5);
select has_function('public','seed_booking_fulfillment_milestones',array['uuid'],'fulfillment seed function exists');
select has_function('public','after_verified_booking_payment',array[]::text[],'verified payment workflow exists');
select has_trigger('public','booking_payment_transactions','after_verified_booking_payment','verified payments seed fulfillment and notifications');
select is(has_function_privilege('authenticated','public.seed_booking_fulfillment_milestones(uuid)','EXECUTE'),false,'customers cannot seed operational tasks');
select is(has_function_privilege('anon','public.seed_booking_fulfillment_milestones(uuid)','EXECUTE'),false,'anonymous users cannot seed operational tasks');
select * from finish();
rollback;
