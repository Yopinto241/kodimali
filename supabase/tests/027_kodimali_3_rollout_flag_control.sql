begin;
select plan(4);
select has_function('public','set_kodimali_feature_flag',array['text','boolean','text','jsonb'],'audited rollout control exists');
select function_is_definer('public','set_kodimali_feature_flag',array['text','boolean','text','jsonb'],'rollout authorization is server-side');
select is(has_function_privilege('anon','public.set_kodimali_feature_flag(text,boolean,text,jsonb)','EXECUTE'),false,'anonymous users cannot control rollout');
select is((select bool_or(enabled) from public.kodimali_feature_flags where key in ('booking_deposit_payments','booking_balance_payments','event_deposit_payments','event_balance_payments','automated_refunds','automated_provider_payouts')),false,'financial automation remains disabled by default');
select * from finish();
rollback;
