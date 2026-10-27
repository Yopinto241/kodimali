begin;
select plan(7);

select has_column('public','booking_policies','cancellation_policy_version_id','booking policy links to cancellation matrix');
select col_is_fk('public','booking_policies','cancellation_policy_version_id','cancellation policy linkage is referentially enforced');
select has_function('public','validate_instant_booking_policy_link',array[]::text[],'instant policy guard exists');
select has_trigger('public','booking_configurations','validate_instant_booking_policy_link','instant configuration enforces linked policy');
select has_function('public','set_booking_policy_cancellation_version',array['uuid','uuid'],'permissioned policy linkage exists');
select function_is_definer('public','set_booking_policy_cancellation_version',array['uuid','uuid'],'policy linkage is server-authoritative');
select is(has_function_privilege('anon','public.set_booking_policy_cancellation_version(uuid,uuid)','EXECUTE'),false,'anonymous users cannot link financial policies');

select * from finish();
rollback;
