begin;
select plan(11);

select has_table('public','commission_reversals','paid commission reversals are explicit');
select col_is_fk('public','commission_reversals','cancellation_case_id','reversal links to cancellation');
select col_is_fk('public','commission_reversals','commission_obligation_id','reversal preserves original obligation');
select col_has_check('public','commission_reversals','status','recovery state is constrained');
select has_function('public','complete_cancellation_dependencies',array[]::text[],'cancellation dependency trigger exists');
select has_trigger('public','booking_cancellation_cases','complete_cancellation_dependencies','approved cancellation handles dependent obligations');
select has_function('public','enforce_booking_payable_recipient',array[]::text[],'payable recipient authority guard exists');
select has_trigger('public','provider_payables','enforce_booking_payable_recipient','booking payable targets controlling owner');
select has_function('public','resolve_booking_incident',array['uuid','text','bigint'],'partial fulfillment resolution exists');
select function_is_definer('public','resolve_booking_incident',array['uuid','text','bigint'],'incident remedy is server-authoritative');
select is(has_function_privilege('anon','public.resolve_booking_incident(uuid,text,bigint)','EXECUTE'),false,'anonymous users cannot approve remedies');

select * from finish();
rollback;
